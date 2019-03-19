defmodule Gelfx do
  @moduledoc """
  A logger backend for Elixir applications using `Logger` and Graylog based on GELF (Graylog extended logging format).

  ## Usage
  Add Gelfx to your application by adding `{:gelfx, "~> 0.1.0"}` to your list of dependencies in `mix.exs`:
  ```elixir
  def deps do
    [
      {:gelfx, "~> 0.1.0"}
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
  - `:protocol` - either `:tcp` or `:udp`, `:http` is not jet supported, defaults to :udp
  - `:format` - defaults to `"$message"`
  - `:host` - hostname of the server running the GELF endpoint
  - `:hostname` - used as source field in the GELF message, defaults to the hostname returned by `:inet.gethostname()`
  - `:json_library` - json library to use, has to implement a `encode/1` which returns a `{:ok, json}` tuple in case of success
  - `:port` - port on which the graylog server runs the respective GELF input
  - `:compression` - either `:gzip` or `:zlib` can be set and will be used for package compression when UDP is used as protocol

  ## Message Format
  The GELF message format version implemented by this library is `1.1` [docs]().

  Messages can include a `short_message` and a `full_message`, Gelfx will use the first line of each log message for the `short_message` and will place the whole message in the `full_message` field.

  Metadata will be included in the message using the `additional field` syntax.
  The Keys of the metadata entries have to match `^\\_?[\\w\\.\\-]*$` with keys missing an leading underscore are automatically prepended with one.
  Key collisions are __NOT__ prevented by Gelfx, additionally the keys `id` and `_id` are automatically omitted due to the GELF spec.

  ## Levels
  Graylog relies on the syslog definitions for logging levels.
  Gelfx maps the Elixir levels as follows:

  | Elixir | Sysylog | GELF - Selector |
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

  alias Logger.Formatter
  alias Gelfx.{LogEntry}

  defstruct [
    :compression,
    :conn,
    :format,
    :host,
    :hostname,
    :json_library,
    :level,
    :metadata,
    :port,
    :protocol
  ]

  @default_conf [
    format: "$message",
    host: "localhost",
    json_library: Jason,
    metadata: [],
    port: 12201,
    protocol: :udp
  ]

  # 2 magic bytes + 8 Msg ID + 1 seq number + 1 seq count
  @chunk_header_bytes 12

  def init(__MODULE__) do
    init({__MODULE__, []})
  end

  def init({__MODULE__, opts}) do
    {:ok, hostname} = :inet.gethostname()

    @default_conf
    |> Keyword.put_new(:hostname, to_string(hostname))
    |> Keyword.merge(Application.get_env(:logger, __MODULE__, []))
    |> Keyword.merge(opts)
    |> init(%__MODULE__{})
  end

  def init(config, %__MODULE__{} = state) do
    state = %__MODULE__{
      state
      | compression: Keyword.get(config, :compression),
        format: Formatter.compile(Keyword.get(config, :format)),
        host: Keyword.get(config, :host),
        hostname: Keyword.get(config, :hostname),
        json_library: Keyword.get(config, :json_library),
        level: Keyword.get(config, :level),
        metadata: Keyword.get(config, :metadata),
        port: Keyword.get(config, :port),
        protocol: Keyword.get(config, :protocol)
    }

    case spawn_conn(state) do
      {:error, _} ->
        {:error, :ignore}

      conn ->
        {:ok, %{state | conn: conn}}
    end
  end

  def handle_call({:configure, options}, state) do
    options
    |> init(state)
    |> case do
      {:ok, state} ->
        {:ok, :ok, state}

      {:error, reason} ->
        raise reason
    end
  end

  def handle_call(_, state) do
    {:ok, :ok, state}
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

  def handle_event(:flush, %{conn: {:tcp, socket}} = state) do
    flush(socket)
    {:ok, state}
  end

  def handle_event(:flush, %{conn: {:udp, {socket, _, _, _}}} = state) do
    flush(socket)
    {:ok, state}
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  def flush(socket) when is_port(socket) do
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

  def handle_info({:tcp_error, _socket, _reason}, state) do
    {:swap_handler, :swap, state, __MODULE__, __MODULE__}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:swap_handler, :swap, state, __MODULE__, __MODULE__}
  end

  def handle_info(_msg, state) do
    {:ok, state}
  end

  def terminate(:swap, state) do
    [
      compression: state.compression,
      host: state.host,
      hostname: state.hostname,
      json_library: state.json_library,
      level: state.level,
      metadata: state.metadata,
      port: state.port,
      protocol: state.protocol
    ]
  end

  def terminate(_reason, %__MODULE__{conn: {:udp, {socket, _, _, _}}}) do
    :gen_udp.close(socket)
  end

  def terminate(_reason, %__MODULE__{conn: {:tcp, socket}}) do
    :gen_tcp.close(socket)
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

  @doc false
  def meet_level?(_lvl, nil), do: true

  def meet_level?(lvl, min) do
    Logger.compare_levels(lvl, min) != :lt
  end

  @doc """
  Spawns a `:gen_udp` / `:gen_tcp` connection based on the configuration
  """
  def spawn_conn(%__MODULE__{
        protocol: protocol,
        host: host,
        port: port
      }) do
    spawn_conn(protocol, host, port)
  end

  def spawn_conn(protocol, host, port) when is_binary(host) do
    spawn_conn(protocol, String.to_charlist(host), port)
  end

  def spawn_conn(:tcp, host, port) do
    :gen_tcp.connect(host, port, [:binary, active: true])
    |> case do
      {:ok, socket} -> {:tcp, socket}
      error -> error
    end
  end

  def spawn_conn(:udp, host, port) do
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

  def submit(payload, {:udp, {socket, host, port, chunk_threshold}}, comp)
      when byte_size(payload) <= chunk_threshold do
    payload =
      case comp do
        :gzip -> :zlib.compress(payload)
        :zlib -> :zlib.gzip(payload)
        _ -> payload
      end

    :gen_udp.send(socket, host, port, payload)
  end

  def submit(payload, {:udp, {_socket, _host, _port, chunk_threshold}} = conn, comp) do
    chunks =
      payload
      |> chunk(chunk_threshold - @chunk_header_bytes)

    chunk_count = length(chunks)

    msg_id = message_id()

    chunks
    |> Enum.map(fn {seq_nr, chunck} ->
      <<0x1E, 0x0F, msg_id::bytes-size(8), seq_nr::8, chunk_count::8, chunck::binary>>
      |> submit(conn, comp)
    end)
  end

  @doc false
  def chunk(binary, chunk_length, sequence_number \\ 0) do
    case binary do
      <<chunk::bytes-size(chunk_length), rest::binary>> ->
        [{sequence_number, chunk} | chunk(rest, chunk_length, sequence_number + 1)]

      _ ->
        [{sequence_number, binary}]
    end
  end

  @doc false
  def message_id() do
    mt = :erlang.monotonic_time()

    ot =
      :os.timestamp()
      |> :calendar.time_to_seconds()

    <<ot::integer-32, mt::integer-32>>
  end
end
