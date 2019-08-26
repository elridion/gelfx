defmodule Gelfx.LogEntryTest do
  use ExUnit.Case

  import Gelfx.LogEntry

  @one_line "Mariaex.Protocol (#PID<0.14976.858>) failed to connect: ** (Mariaex.Error) tcp connect: timeout"

  @multi_line ~S"Ranch protocol #PID<0.11579.883> of listener MyApp.Api.Endpoint.HTTP (cowboy_protocol) terminated
  ** (exit) exited in: :gen_server.call(#PID<0.2317.161>, {:checkout, #Reference<0.2120201426.1365770241.236930>, true, 15000}, 9000)
      ** (EXIT) time out
  "

  test "short message" do
    assert @one_line == short_message(@one_line)

    assert "Ranch protocol #PID<0.11579.883> of listener MyApp.Api.Endpoint.HTTP (cowboy_protocol) terminated" ==
             short_message(@multi_line)
  end
end
