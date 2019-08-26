defmodule Gelfx do
  @moduledoc """
  A logger backend for Elixir applications using `Logger` and Graylog based on GELF (Graylog extended logging format).

  ## Usage
  Add Gelfx to your application by adding `{:gelfx, "~> #{Mix.Project.config()[:version]}"}` to your list of dependencies in `mix.exs`:
  ```elixir
  def deps do
    [
      # ...
      {:gelfx, "~> #{Mix.Project.config()[:version]}"}
    ]
  end
  ```
  And adding it to your `:logger` configuration in `config.exs`:
  ```elixir
  config :logger,
    backends: [
      :console,
      Gelfx
    ]
  ```
  Since GELF relies on json to encode the payload Gelfx will need a JSON library. By default Gelfx will use Jason which needs to be added to your deps in mix.exs:

      {:jason, "~> 1.0"}

  ## Options
  Besides `:level`, `:format` and `:metadata`, which are advised by [Logger](https://hexdocs.pm/logger/Logger.html#module-custom-backends) Gelfx supports:
  - `:host` - hostname of the server running the GELF endpoint, defaults to `localhost`
  - `:port` - port on which the graylog server runs the respective GELF input, defaults to `12201`
  - `:protocol` - either `:tcp`, `:udp`, or `:http`.  Defaults to `:udp`.
  - `:connection_timeout` - sets the timeout in ms after which the `:tcp` connect timeouts, defaults to 5s.
  - `:compression` - either `:gzip` or `:zlib` can be set and will be used for package compression when UDP or HTTP (only gzip) is used as protocol
  - `:format` - defaults to `"$message"`
  - `:hostname` - used as source field in the GELF message, defaults to the hostname returned by `:inet.gethostname()`
  - `:json_library` - json library to use, has to implement a `encode/1` which returns a `{:ok, json}` tuple in case of success
  - `:utc_log` - this option should not be configured directly. But rather by setting the `:utc_log` option in the `Logger` config. Should the Logger config change after the Gelfx backend is initialized the option has to be reconfigured.

  ### HTTP
  When using the HTTP protocol the url is build using the scheme defined in the graylog [documentation](https://docs.graylog.org/en/3.1/pages/sending_data.html#gelf-via-http).

  Setting the host to `localhost` and port to `12201` sends log entries to `http://localhost:12201/gelf`.

  ## Message Format
  The GELF message format version implemented by this library is 1.1, the docs can be found [here](http://docs.graylog.org/en/3.0/pages/gelf.html).

  Messages can include a `short_message` and a `full_message`, Gelfx will use the first line of each log message for the `short_message` and will place the whole message in the `full_message` field.

  Metadata will be included in the message using the _additional field_ syntax.
  The Keys of the metadata entries have to match `^\\_?[\\w\\.\\-]*$`, keys missing an leading underscore are automatically prepended with one.
  Key collisions are __NOT__ prevented by Gelfx, additionally the keys `id` and `_id` are automatically omitted due to the GELF specification.

  ## Levels
  Graylog relies on the syslog definitions for logging levels.
  Gelfx maps the Elixir levels as follows:

  | Elixir | Syslog | GELF - Selector |
  |-|-|-|
  | | Emergency | 0 |
  | | Alert | 1 |
  | | Critical | 2 |
  | `:error` | Error | 3 |
  | `:warn` | Warning | 4 |
  | | Notice | 5 |
  | `:info` | Informational | 6 |
  | `:debug` | Debug | 7 |
  """

  # Copyright 2019 Hans Bernhard Goedeke
  #
  # Licensed under the Apache License, Version 2.0 (the "License");
  # you may not use this file except in compliance with the License.
  # You may obtain a copy of the License at
  #
  #     http://www.apache.org/licenses/LICENSE-2.0
  #
  # Unless required by applicable law or agreed to in writing, software
  # distributed under the License is distributed on an "AS IS" BASIS,
  # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  # See the License for the specific language governing permissions and
  # limitations under the License.

  @behaviour :gen_event

  @after_compile __MODULE__

  require Logger

  alias Logger.Formatter
  alias Gelfx.{LogEntry}

  defstruct [
    :compression,
    :conn,
    :connection_timeout,
    :format,
    :host,
    :hostname,
    :json_library,
    :level,
    :metadata,
    :port,
    :protocol,
    :utc_log
  ]

  @default_conf [
    connection_timeout: 5_000,
    format: "$message",
    host: "localhost",
    json_library: Jason,
    metadata: [],
    port: 12201,
    protocol: :udp
  ]

  # 2 magic bytes + 8 Msg ID + 1 seq number + 1 seq count
  @chunk_header_bytes 12

  def __after_compile__(%{line: line, file: file}, _bytecode) do
    json_library =
      default_conf()
      |> Keyword.merge(Application.get_env(:logger, __MODULE__, []))
      |> Keyword.get(:json_library)

    cond do
      not Code.ensure_compiled?(json_library) ->
        IO.warn(
          [
            "JSON library ",
            inspect(json_library),
            " is not available"
          ],
          [{__MODULE__, :__MODULE__, 1, [file: to_charlist(file), line: line]}]
        )

      not ({:encode, 1} in json_library.__info__(:functions)) ->
        IO.warn(
          [
            "JSON library ",
            inspect(json_library),
            " does not implement a public function encode/1 "
          ],
          [{__MODULE__, :__MODULE__, 1, [file: to_charlist(file), line: line]}]
        )

      true ->
        case apply(json_library, :encode, [%{}]) do
          {:ok, _} ->
            :ok

          _ ->
            IO.warn(
              [
                "JSON library ",
                inspect(json_library),
                " function encode/1 does not return an {:ok, json} tuple"
              ],
              [{__MODULE__, :__MODULE__, 1, [file: to_charlist(file), line: line]}]
            )
        end
    end
  end

  @impl true
  def init(__MODULE__) do
    config = Keyword.merge(default_conf(), Application.get_env(:logger, __MODULE__, []))
    init({__MODULE__, config})
  end

  def init({__MODULE__, options}) do
    {:ok, config(options, %__MODULE__{})}
  end

  defp init(config, %__MODULE__{} = state) do
    state = %__MODULE__{
      state
      | compression: Keyword.get(config, :compression),
        connection_timeout: Keyword.get(config, :connection_timeout),
        format: Formatter.compile(Keyword.get(config, :format)),
        host: Keyword.get(config, :host),
        hostname: Keyword.get(config, :hostname),
        json_library: Keyword.get(config, :json_library),
        level: Keyword.get(config, :level),
        metadata: Keyword.get(config, :metadata),
        port: Keyword.get(config, :port),
        protocol: Keyword.get(config, :protocol),
        utc_log: Keyword.get(config, :utc_log)
    }

    case :ets.info(__MODULE__, :size) do
      :undefined ->
        :ets.new(__MODULE__, [:public, :duplicate_bag, :named_table])

      0 ->
        :ok

      _ ->
        send(self(), {__MODULE__, :flush_buffer})
    end

    case spawn_conn(state) do
      {:error, reason} ->
        Logger.error(["Cloud not establish connection on init ", inspect(reason)])
        %{state | conn: :error}

      conn ->
        %{state | conn: conn}
    end
  end

  defp config(options, state) do
    config = Keyword.merge(Application.get_env(:logger, __MODULE__, []), options)

    Application.put_env(:logger, __MODULE__, config)

    init(config, state)
  end

  @impl true
  def handle_call({:configure, options}, state) do
    {:ok, :ok, config(options, state)}
  end

  def handle_call(_, state) do
    {:ok, :ok, state}
  end

  @impl true
  def handle_event(event, %{conn: :error} = state) do
    case handle_info(:retry, state) do
      {:ok, state} ->
        handle_event(event, state)

      error ->
        error
    end
  end

  def handle_event(_, %{conn: {:retry, :discard}} = state) do
    {:ok, state}
  end

  def handle_event(
        {level, group_leader, {Logger, _message, _timestamp, _metadata}} = event,
        %{conn: {:retry, _mode}} = state
      ) do
    if meet_level?(level, state.level) and node(group_leader) == node() do
      :ets.insert(__MODULE__, {:erlang.monotonic_time(), event})
    end

    {:ok, state}
  end

  def handle_event(
        {level, group_leader, {Logger, _message, _timestamp, _metadata}} = event,
        state
      ) do
    if meet_level?(level, state.level) and node(group_leader) == node() do
      event
      |> LogEntry.from_event(state)
      |> encode(state)
      |> case do
        {:ok, json} ->
          submit(json, state)

        error ->
          error
      end
    end

    {:ok, state}
  end

  def handle_event(:flush, state) do
    flush(state.conn)
    {:ok, state}
  end

  def handle_event(_event, state) do
    {:ok, state}
  end

  @impl true
  def handle_info({__MODULE__, msg}, state) do
    handle_info(msg, state)
  end

  def handle_info({:tcp_error, socket, reason}, state) do
    case state do
      %{conn: {:tcp, ^socket}} ->
        Logger.warn(["TCP connection error ", inspect(reason)])
        handle_info(:retry, close_conn(state))

      _ ->
        {:ok, state}
    end
  end

  def handle_info({:tcp_closed, socket}, state) do
    case state do
      %{conn: {:tcp, ^socket}} ->
        Logger.warn("TCP connection closed")
        handle_info(:retry, close_conn(state))

      _ ->
        {:ok, state}
    end
  end

  def handle_info(:flush_buffer, %{conn: {prot, _}} = state)
      when prot in [:tcp, :udp] do
    case :ets.first(__MODULE__) do
      :"$end_of_table" ->
        {:ok, state}

      key ->
        send(self(), :flush_buffer)

        Enum.reduce(
          :ets.take(__MODULE__, key),
          {:ok, state},
          fn {_, event}, acc ->
            case acc do
              {:ok, state} ->
                handle_event(event, state)

              error ->
                error
            end
          end
        )
    end
  end

  def handle_info(:retry, state) do
    if state.conn in [:error, nil], do: Logger.debug("Connection error starting retries")

    case spawn_conn(state) do
      {:error, _reason} ->
        Process.send_after(self(), :retry, state.connection_timeout)

        mode =
          if discard?() do
            :discard
          else
            :store
          end

        {:ok, %{state | conn: {:retry, mode}}}

      conn ->
        Logger.info("Connection established flushing buffer")
        handle_info(:flush_buffer, %{state | conn: conn})
    end
  end

  def handle_info(_msg, state) do
    {:ok, state}
  end

  @impl true
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  @impl true
  def terminate(:swap, state) do
    state = close_conn(state)

    [
      compression: state.compression,
      format: state.format,
      host: state.host,
      json_library: state.json_library,
      level: state.level,
      metadata: state.metadata,
      port: state.port,
      protocol: state.protocol
    ]
  end

  def terminate(_reason, state) do
    close_conn(state)
    :ets.delete(__MODULE__)
  end

  @doc """
  Encodes the given `LogEntry` using the configured json library
  """
  def encode(%LogEntry{} = log_entry, %__MODULE__{} = state) do
    log_entry
    |> Map.from_struct()
    |> encode(state)
  end

  def encode(log_entry, %__MODULE__{json_library: json}) when is_map(log_entry) do
    apply(json, :encode, [log_entry])
  end

  @compile {:inline, meet_level?: 2}
  @doc false
  def meet_level?(_lvl, nil), do: true

  def meet_level?(lvl, min) do
    Logger.compare_levels(lvl, min) != :lt
  end

  @doc """
  Spawns a `:gen_udp` / `:gen_tcp` connection based on the configuration
  """
  def spawn_conn(%__MODULE__{conn: {prot, _socket} = conn} = state) when prot in [:udp, :tcp] do
    flush(conn)

    state
    |> close_conn()
    |> spawn_conn()
  end

  def spawn_conn(%__MODULE__{
        protocol: protocol,
        host: host,
        port: port,
        connection_timeout: timeout
      }) do
    spawn_conn(protocol, host, port, timeout)
  end

  def spawn_conn(protocol, host, port, timeout) when is_binary(host) do
    spawn_conn(protocol, String.to_charlist(host), port, timeout)
  end

  def spawn_conn(:tcp, host, port, timeout) do
    case :gen_tcp.connect(host, port, [:binary, active: true], timeout) do
      {:ok, socket} -> {:tcp, socket}
      error -> error
    end
  end

  def spawn_conn(:udp, host, port, _timeout) do
    case :gen_udp.open(0, [:binary, active: true]) do
      {:ok, socket} ->
        buffer =
          case :inet.getopts(socket, [:buffer]) do
            {:ok, [buffer: buffer]} -> buffer
            _ -> 8192
          end

        {:udp, {socket, host, port, buffer}}

      error ->
        error
    end
  end

  def spawn_conn(:http, host, port, _timeout) do
    :inets.start()

    {:http, List.flatten(['http://', host, ?:, Integer.to_charlist(port) | '/gelf'])}
  end

  @doc false
  def close_conn(%__MODULE__{conn: connection} = state) do
    case close_conn(connection) do
      :ok -> %{state | conn: nil}
      :error -> state
    end
  end

  def close_conn({:tcp, socket}) do
    :gen_tcp.close(socket)
  end

  def close_conn({:udp, {socket, _host, _post, _buffer}}) do
    :gen_udp.close(socket)
  end

  def close_conn({:http, _}) do
    :ok
  end

  def close_conn(_) do
    :error
  end

  @doc """
  Sends the given payload over the connection.

  In case an TCP connection is used the `0x00` delimiter required by gelf is added.

  Should the used connection use UDP the payload is compressed using the configured compression, in case the given payload exceeds the chunk threshold it is chunked.
  """
  def submit(payload, %__MODULE__{conn: conn, compression: comp}) do
    submit(payload, conn, comp)
  end

  def submit(payload, {:tcp, socket}, _compression) do
    :gen_tcp.send(socket, payload <> <<0>>)
  end

  def submit(payload, {:udp, _} = conn, comp)
      when not is_nil(comp) do
    case comp do
      :gzip ->
        :zlib.gzip(payload)

      :zlib ->
        :zlib.compress(payload)

      _ ->
        payload
    end
    |> submit(conn, nil)
  end

  def submit(payload, {:udp, {socket, host, port, chunk_threshold}}, _comp)
      when byte_size(payload) <= chunk_threshold do
    :gen_udp.send(socket, host, port, payload)
  end

  def submit(payload, {:udp, {_socket, _host, _port, chunk_threshold}} = conn, comp) do
    chunks = chunk(payload, chunk_threshold - @chunk_header_bytes)
    chunk_count = length(chunks)
    msg_id = message_id()

    for {seq_nr, chunck} <- chunks do
      <<0x1E, 0x0F, msg_id::bytes-size(8), seq_nr::8, chunk_count::8, chunck::binary>>
      |> submit(conn, comp)
    end
  end

  def submit(payload, {:http, url}, :gzip) do
    :httpc.request(
      :post,
      {url, [{'Content-Encoding', 'gzip'}], 'application/json', :zlib.gzip(payload)},
      [],
      []
    )
  end

  def submit(payload, {:http, url}, _comp) do
    :httpc.request(:post, {url, [], 'application/json', payload}, [], [])
  end

  defp flush({:tcp, socket}) do
    flush(socket)
  end

  defp flush({:udp, {socket, _host, _post, _buffer}}) do
    flush(socket)
  end

  defp flush(socket) when is_port(socket) do
    case :inet.getstat(socket, [:send_pend]) do
      {:ok, [send_pend: 0]} ->
        :ok

      {:ok, _} ->
        Process.sleep(10)
        flush(socket)

      _ ->
        :error
    end
  end

  defp flush({:http, _}) do
    :ok
  end

  defp flush(_) do
    :error
  end

  defp chunk(binary, chunk_length, sequence_number \\ 0) do
    case binary do
      <<chunk::bytes-size(chunk_length), rest::binary>> ->
        [{sequence_number, chunk} | chunk(rest, chunk_length, sequence_number + 1)]

      _ ->
        [{sequence_number, binary}]
    end
  end

  defp message_id do
    mt = :erlang.monotonic_time()

    ot =
      :os.timestamp()
      |> :calendar.time_to_seconds()

    <<ot::integer-32, mt::integer-32>>
  end

  defp discard? do
    :ets.info(__MODULE__, :size) >= Application.get_env(:logger, :discard_threshold, 500) * 10
  end

  defp hostname do
    {:ok, hostname} = :inet.gethostname()
    to_string(hostname)
  end

  defp default_conf do
    @default_conf
    |> Keyword.put(:hostname, hostname())
    |> Keyword.put(:utc_log, Application.get_env(:logger, :utc_log, false))
  end
end
