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

  describe "from_event/2" do
    setup context do
      gelfx = %Gelfx{
        format: {TestFormatter, :format},
        metadata: [meta: "test"],
        hostname: "test.local",
        utc_log: true
      }

      Map.merge(context, %{gelfx: gelfx})
    end

    test "allows custom logger format module", %{gelfx: gelfx} do
      event =
        {4, nil,
         {Logger, "test-message", {{2021, 01, 01}, {01, 01, 01, 01}},
          [email: "email@test.local"]}}

      entry = Gelfx.LogEntry.from_event(event, gelfx)

      assert entry[:full_message] == "[test-logger][4] test-message\n"
      assert entry[:host] == "test.local"
      assert entry[:short_message] == "[test-logger][4] test-message"
      assert entry[:timestamp]
      assert entry[:version]
      assert entry["_email"] == "email@test.local"
      assert entry["_meta"] == "test"
    end

    test "uses default log message if issues with custom logger format" do
      event =
        {4, nil,
         {Logger, "test-message", {{2021, 01, 01}, {01, 01, 01, 01}},
          [email: "email@test.local"]}}

      entry = Gelfx.LogEntry.from_event(event, %Gelfx{
        format: {TestFormatter, :bad_format},
        hostname: "test.local",
        utc_log: true,
        metadata: []
      })
      assert entry[:full_message] == "test-message"
      assert entry[:host] == "test.local"
      assert entry[:short_message] == "test-message"
      assert entry[:timestamp]
      assert entry[:version]
      assert entry["_email"] == "email@test.local"
    end
  end
end
