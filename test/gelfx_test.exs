defmodule GelfxTest do
  use ExUnit.Case, async: false, capture_log: true
  require Logger
  alias TestHelper.{TcpServer, UdpServer}
  doctest Gelfx

  @logging_wait 1000

  describe "TCP Test" do
    setup do
      Logger.configure(utc_log: false)

      {:ok, server} = start_tcp()
      # start_tcp()
      Logger.add_backend(Gelfx)
      Logger.configure_backend(Gelfx, protocol: :tcp, level: :info)
      TcpServer.listen()

      on_exit(&stop_tcp/0)
      on_exit(fn -> Logger.remove_backend(Gelfx) end)

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

      assert ets_size() == 0
      info("send_offline0")
      assert ets_size() == 1
      info("send_offline1")
      assert ets_size() == 2
      info("send_offline2")
      assert ets_size() == 3
      info("send_offline3")
      assert ets_size() == 4
      start_tcp()
      Process.sleep(6000)
      assert ets_size() == 0
      info("send_online")
      assert ets_size() == 0

      tcp_messages =
        TcpServer.all()
        |> Enum.map(&Map.get(&1, "full_message"))
        |> Enum.sort()

      messages =
        [
          "send_offline0",
          "send_offline1",
          "send_offline2",
          "send_offline3",
          "send_online"
        ]
        |> Enum.sort()

      assert tcp_messages == messages
    end

    @tag :tcp
    test "cache discard" do
      Logger.configure_backend(Gelfx, level: :error)
      Process.sleep(@logging_wait)
      TcpServer.listen()
      debug("debug")
      info("info")
      warn("warn")
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

      Logger.configure(utc_log: true)
      Logger.configure_backend(Gelfx, utc_log: true)
      TcpServer.listen()

      now = :os.system_time(:seconds)

      info("log in utc")
      assert %{"timestamp" => timestamp} = TcpServer.pop()
      assert_in_delta(timestamp, now, 2)
    end
  end

  describe "UDP Test" do
    setup do
      Logger.configure(utc_log: false)

      {:ok, server} = start_udp()
      Logger.add_backend(Gelfx)
      Logger.configure_backend(Gelfx, protocol: :udp, level: :info)

      on_exit(&stop_udp/0)
      on_exit(fn -> Logger.remove_backend(Gelfx) end)

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
    #   Logger.configure_backend(Gelfx, compression: :gzip)
    #   Process.sleep(@logging_wait)

    #   info("hiho was sind wir froh")

    #   msg = UdpServer.pop()
    #   assert is_binary(msg) == true
    #   asset(gunzipped = :zlib.gunzip(msg))

    #   # assert {:ok, uncompressed} = :gzip.

    #   # assert %{"full_message" => "hiho was sind wir froh"} =
    #   Logger.configure_backend(Gelfx, compression: nil)
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

  defp warn(msg) do
    Logger.warn(msg)
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
end
