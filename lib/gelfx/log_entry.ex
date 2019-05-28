defmodule Gelfx.LogEntry do
  @moduledoc false
  alias Logger.Formatter

  @gelf_version "1.1"

  @unix_epoch 62_167_219_200

  @enforce_keys [:version, :host, :short_message]
  defstruct [
    :host,
    :short_message,
    :full_message,
    :timestamp,
    :level,
    version: @gelf_version
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
      )
      when is_list(format) do
    metadata = Keyword.merge(metadata, additional_metadata)

    full_message =
      format
      |> Formatter.format(level, message, timestamp, metadata)
      |> IO.chardata_to_string()

    short_message =
      String.split(full_message, "\n")
      |> List.first()

    timestamp =
      if utc? do
        timestamp
      else
        timestamp_to_utc(timestamp)
      end
      |> timestamp_to_unix()

    %__MODULE__{
      version: @gelf_version,
      host: hostname,
      short_message: short_message,
      full_message: full_message,
      timestamp: timestamp,
      level: log_level(level)
    }
    |> Map.from_struct()
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

  def log_level(level) do
    case level do
      :error -> 3
      :warn -> 4
      :info -> 6
      :debug -> 7
    end
  end

  def timestamp_to_unix({date, {hour, minute, second, millisecond}}) do
    timestamp_to_unix({date, {hour, minute, second}}) + millisecond / 1000
  end

  def timestamp_to_unix({_d, {_h, _m, _s}} = datetime) do
    datetime
    |> :calendar.datetime_to_gregorian_seconds()
    |> (fn timestamp -> timestamp - @unix_epoch end).()
  end

  def timestamp_to_utc({date, {hour, minute, second, millisecond}}) do
    {utc_date, {utc_hour, utc_minute, utc_second}} =
      timestamp_to_utc({date, {hour, minute, second}})

    {utc_date, {utc_hour, utc_minute, utc_second, millisecond}}
  end

  def timestamp_to_utc({_d, {_h, _m, _s}} = datetime) do
    :calendar.local_time_to_universal_time(datetime)
  end
end
