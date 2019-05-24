defmodule GelfxTest do
  use ExUnit.Case, async: false
  require Logger
  alias TestHelper.TcpServer
  doctest Gelfx

  @logging_wait 250

  setup do
    {:ok, server} = start_tcp()
    Logger.add_backend(Gelfx)

    on_exit(&stop_tcp/0)
    on_exit(fn -> Logger.remove_backend(Gelfx) end)

    {:ok, server: server}
  end

  test "logging" do
    info("hello world")

    Process.sleep(@logging_wait)
    assert %{"full_message" => "hello world"} = TcpServer.pop()
  end

  test "connection loss" do
    info("hello")
    stop_tcp()

    assert :ets.info(Gelfx, :size) == 0
    # Process.sleep(100)
    info("send_offline0")
    info("send_offline1")
    info("send_offline2")
    info("send_offline3")
    assert :ets.info(Gelfx, :size) == 4
    start_tcp()
    Process.sleep(6000)
    assert :ets.info(Gelfx, :size) == 0
    info("send_online")
    assert :ets.info(Gelfx, :size) == 0

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

  defp start_tcp do
    {:ok, _} = GenServer.start(TcpServer, [], name: TcpServer)
  end

  defp stop_tcp do
    GenServer.stop(TcpServer)
  end

  defp debug(msg) do
    Logger.debug(msg)
    Logger.flush()
  end

  defp info(msg) do
    Logger.info(msg)
    Logger.flush()
  end

  defp warn(msg) do
    Logger.warn(msg)
    Logger.flush()
  end

  defp error(msg) do
    Logger.error(msg)
    Logger.flush()
  end
end
