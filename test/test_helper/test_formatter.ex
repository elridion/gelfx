defmodule TestFormatter do
  def format(level, message, timestamp, metadata) do
    "[test-logger][#{level}] #{message}\n"
  rescue
    _ -> "could not format message!\n"
  end
end
