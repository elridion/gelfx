defmodule Gelfx.LogEntry do
  @moduledoc false
  alias Logger.Formatter

  @gelf_version "1.1"

  @unix_epoch 62_167_219_200

  @default_message_format "[$level] $message\n"

  @loglevel [
    emergency: 0,
    alert: 1,
    critical: 2,
    error: 3,
    warn: 4,
    warning: 4,
    notice: 5,
    info: 6,
    debug: 7
  ]

  def from_event(event, %Gelfx{
        format: format,
        metadata: metadata,
        hostname: hostname,
        utc_log: utc?
      }) do
    from_event(event, format, metadata, hostname, utc?)
  end

  def from_event(
        {level, _group_leader, {Logger, message, timestamp, metadata}},
        format,
        additional_metadata,
        hostname,
        utc?
      ) do
    metadata = Keyword.merge(metadata, additional_metadata)

    full_message = formatted_full_message(format, level, message, timestamp, metadata)

    short_message = short_message(full_message)

    timestamp =
      if utc? do
        timestamp
      else
        timestamp_to_utc(timestamp)
      end
      |> timestamp_to_unix()

    %{
      version: @gelf_version,
      host: hostname,
      short_message: short_message,
      full_message: full_message,
      timestamp: timestamp,
      level: log_level(level)
    }
    |> add_metadata(metadata)
  end

  def add_metadata(log_entry, []) do
    log_entry
  end

  def add_metadata(log_entry, [entry | rest]) do
    log_entry
    |> add_metadata(entry)
    |> add_metadata(rest)
  end

  def add_metadata(log_entry, {key, value}) do
    value
    |> case do
      %NaiveDateTime{} ->
        NaiveDateTime.to_iso8601(value)

      %Date{} ->
        Date.to_iso8601(value)

      %DateTime{} ->
        DateTime.to_iso8601(value)

      value ->
        cond do
          is_binary(value) and String.valid?(value) ->
            value

          is_number(value) ->
            value

          is_atom(value) ->
            Atom.to_string(value)

          true ->
            :error
        end
    end
    |> case do
      :error ->
        log_entry

      value ->
        case get_key(key) do
          {:ok, key} -> Map.put_new(log_entry, key, value)
          :error -> log_entry
        end
    end
  end

  def get_key(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> get_key()
  end

  def get_key("_id") do
    :error
  end

  def get_key(<<"_", rest::binary>> = key) do
    if String.valid?(key) and String.match?(rest, ~r/^[\w\.\-]*$/) do
      {:ok, key}
    else
      :error
    end
  end

  def get_key(key) when is_binary(key) do
    get_key("_" <> key)
  end

  for {ex_level, gelf_selector} <- @loglevel do
    def log_level(unquote(ex_level)) do
      unquote(gelf_selector)
    end
  end

  def log_level(_) do
    0
  end

  def timestamp_to_unix({date, {hour, minute, second, millisecond}}) do
    timestamp_to_unix({date, {hour, minute, second}}) + millisecond / 1000
  end

  def timestamp_to_unix({_d, {_h, _m, _s}} = datetime) do
    :calendar.datetime_to_gregorian_seconds(datetime) - @unix_epoch
  end

  def timestamp_to_utc({date, {hour, minute, second, millisecond}}) do
    [{utc_date, {utc_hour, utc_minute, utc_second}}] =
      timestamp_to_utc({date, {hour, minute, second}})

    {utc_date, {utc_hour, utc_minute, utc_second, millisecond}}
  end

  def timestamp_to_utc({_d, {_h, _m, _s}} = datetime) do
    :calendar.local_time_to_universal_time_dst(datetime)
  end

  def short_message(data) do
    short_message(data, data, 0)
  end

  def short_message(<<?\n, _rest::binary>>, original, length) do
    binary_part(original, 0, length)
  end

  for {bound, length} <- [{0x7F, 1}, {0x7FF, 2}, {0xFFFF, 3}] do
    def short_message(<<char::utf8, rest::binary>>, original, length)
        when char <= unquote(bound) do
      short_message(rest, original, length + unquote(length))
    end
  end

  def short_message(<<_char::utf8, rest::binary>>, original, length) do
    short_message(rest, original, length + 4)
  end

  def short_message(<<>>, original, _length) do
    original
  end

  defp formatted_full_message({module, func}, level, message, timestamp, metadata) do
    try do
      with true <- Code.ensure_loaded?(module),
           true <- function_exported?(module, func, 4) do
        apply(module, func, [level, message, timestamp, metadata])
      else
        _ ->
          compiled_default_message_format
      end
    rescue
      _ ->
        compiled_default_message_format
    end
  end

  defp formatted_full_message(format, level, message, timestamp, metadata) do
    format
    |> Formatter.format(level, message, timestamp, metadata)
    |> IO.chardata_to_string()
  end

  defp compiled_default_message_format do
    Logger.Formatter.compile(@default_message_format)
  end
end
