defmodule GelfxTest do
  use ExUnit.Case, async: false

  alias TestHelper.TcpServer
  alias TestHelper.UdpServer

  require Logger

  doctest Gelfx

  @logging_wait 1000

  describe "TCP Test" do
    setup do
      LoggerBackends.configure(utc_log: false)

      {:ok, server} = start_tcp()
      # start_tcp()
      LoggerBackends.add(Gelfx)
      LoggerBackends.configure(Gelfx, protocol: :tcp, level: :info)
      TcpServer.listen()

      on_exit(&stop_tcp/0)
      on_exit(fn -> LoggerBackends.remove(Gelfx) end)

      {:ok, server: server}
    end

    @tag :tcp
    test "logging" do
      info("hello world")
      assert %{"full_message" => "hello world"} = TcpServer.pop()
    end

    @tag :tcp
    test "connection loss" do
      info("hello")
      Process.sleep(@logging_wait)
      assert %{"full_message" => "hello"} = TcpServer.pop()
      stop_tcp()

      # The backend learns about the dropped connection asynchronously, via the
      # `{:tcp_closed, socket}` message. Only once it has switched to buffering
      # mode are logged events stored in ETS; a message logged before then races
      # the detection and is submitted to the dead socket (and lost). Wait for
      # the actual condition instead of assuming detection is synchronous.
      assert wait_until(fn -> match?({:retry, _}, gelfx_conn()) end)

      assert ets_size() == 0
      info("send_offline0")
      assert wait_until(fn -> ets_size() == 1 end)
      info("send_offline1")
      assert wait_until(fn -> ets_size() == 2 end)
      info("send_offline2")
      assert wait_until(fn -> ets_size() == 3 end)
      info("send_offline3")
      assert wait_until(fn -> ets_size() == 4 end)
      start_tcp()
      # Reconnection is driven by a periodic `:retry` (every `connection_timeout`,
      # 5s by default), which flushes the buffer on success. Poll for the drained
      # buffer rather than sleeping a fixed, hopeful interval.
      assert wait_until(fn -> ets_size() == 0 end, 10_000)
      info("send_online")
      assert ets_size() == 0

      tcp_messages =
        TcpServer.all()
        |> Enum.map(&Map.get(&1, "full_message"))
        |> Enum.sort()

      messages =
        Enum.sort([
          "send_offline0",
          "send_offline1",
          "send_offline2",
          "send_offline3",
          "send_online"
        ])

      assert tcp_messages == messages
    end

    @tag :tcp
    test "cache discard" do
      LoggerBackends.configure(Gelfx, level: :error)
      Process.sleep(@logging_wait)
      TcpServer.listen()
      debug("debug")
      info("info")
      warning("warning")
      error("error")
      Process.sleep(@logging_wait)
      assert [%{"full_message" => "error"}] = TcpServer.all()
    end

    @tag :tcp
    test "logging time" do
      now = :os.system_time(:seconds)
      info("log in local")
      assert %{"timestamp" => timestamp} = TcpServer.pop()
      assert_in_delta(timestamp, now, 2)

      LoggerBackends.configure(utc_log: true)
      LoggerBackends.configure(Gelfx, utc_log: true)
      TcpServer.listen()

      now = :os.system_time(:seconds)

      info("log in utc")
      assert %{"timestamp" => timestamp} = TcpServer.pop()
      assert_in_delta(timestamp, now, 2)
    end
  end

  describe "UDP Test" do
    setup do
      LoggerBackends.configure(utc_log: false)

      {:ok, server} = start_udp()
      LoggerBackends.add(Gelfx)
      LoggerBackends.configure(Gelfx, protocol: :udp, level: :info)

      on_exit(&stop_udp/0)
      on_exit(fn -> LoggerBackends.remove(Gelfx) end)

      {:ok, server: server}
    end

    @tag :udp
    test "logging" do
      info("hello world")
      assert %{"full_message" => "hello world"} = UdpServer.pop()
    end

    # @tag :udp
    # test "chunking" do
    #   many_infos = String.duplicate("info", 1050)

    #   info(many_infos)
    #   # assert %{"full_message" => ^many_infos} = UdpServer.pop()
    # end

    # @tag :udp
    # @tag :gzip
    # test "compression" do
    #   LoggerBackends.configure(Gelfx, compression: :gzip)
    #   Process.sleep(@logging_wait)

    #   info("hiho was sind wir froh")

    #   msg = UdpServer.pop()
    #   assert is_binary(msg) == true
    #   asset(gunzipped = :zlib.gunzip(msg))

    #   # assert {:ok, uncompressed} = :gzip.

    #   # assert %{"full_message" => "hiho was sind wir froh"} =
    #   LoggerBackends.configure(Gelfx, compression: nil)
    # end
  end

  defp start_tcp do
    {:ok, _} = GenServer.start(TcpServer, [], name: TcpServer)
  end

  defp stop_tcp do
    GenServer.stop(TcpServer)
  end

  defp start_udp do
    {:ok, _} = GenServer.start(UdpServer, [], name: UdpServer)
  end

  defp stop_udp do
    GenServer.stop(UdpServer)
  end

  defp debug(msg) do
    Logger.debug(msg)
    Logger.flush()
    Process.sleep(@logging_wait)
  end

  defp info(msg) do
    Logger.info(msg)
    Logger.flush()
    Process.sleep(@logging_wait)
  end

  defp warning(msg) do
    Logger.warning(msg)
    Logger.flush()
    Process.sleep(@logging_wait)
  end

  defp error(msg) do
    Logger.error(msg)
    Logger.flush()
    Process.sleep(@logging_wait)
  end

  defp ets_size do
    :ets.info(Gelfx, :size)
  end

  # Returns the Gelfx backend's current connection state (e.g. `{:tcp, port}`,
  # `{:retry, :store}`) by introspecting the gen_event manager that hosts it.
  defp gelfx_conn do
    LoggerBackends
    |> :sys.get_state()
    |> Enum.find_value(fn
      {Gelfx, _id, state} -> Map.get(state, :conn)
      _ -> nil
    end)
  end

  # Polls `fun` until it returns a truthy value or the timeout elapses. Returns
  # the truthy value, or `false` on timeout so it reads well inside `assert`.
  defp wait_until(fun, timeout \\ 5_000) do
    wait_until(fun, timeout, System.monotonic_time(:millisecond))
  end

  defp wait_until(fun, timeout, started) do
    cond do
      result = fun.() ->
        result

      System.monotonic_time(:millisecond) - started > timeout ->
        false

      true ->
        Process.sleep(20)
        wait_until(fun, timeout, started)
    end
  end
end
