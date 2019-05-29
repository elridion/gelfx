defmodule GelfxTest do
  use ExUnit.Case, async: false
  require Logger
  alias TestHelper.TcpServer
  doctest Gelfx

  @logging_wait 250

  setup do
    Logger.configure(utc_log: false)

    {:ok, server} = start_tcp()
    Logger.add_backend(Gelfx)

    on_exit(&stop_tcp/0)
    on_exit(fn -> Logger.remove_backend(Gelfx) end)

    {:ok, server: server}
  end

  test "logging" do
    info("hello world")
    assert %{"full_message" => "hello world"} = TcpServer.pop()
  end

  test "connection loss" do
    info("hello")
    Process.sleep(@logging_wait)

    stop_tcp()

    assert ets_size() == 0
    info("send_offline0")
    assert ets_size() == 1
    info("send_offline1")
    assert ets_size() == 2
    info("send_offline2")
    assert ets_size() == 3
    info("send_offline3")
    Process.sleep(@logging_wait)
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

  test "cache discard" do
    Logger.configure_backend(Gelfx, level: :error)
    TcpServer.listen()
    Process.sleep(@logging_wait)
    debug("debug")
    info("info")
    warn("warn")
    error("error")
    Process.sleep(@logging_wait)
    assert [%{"full_message" => "error"}] = TcpServer.all()
  end

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

  defp start_tcp do
    {:ok, _} = GenServer.start(TcpServer, [], name: TcpServer)
  end

  defp stop_tcp do
    GenServer.stop(TcpServer)
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
