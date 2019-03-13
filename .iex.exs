require Logger

Logger.info("test")
spawn(fn -> raise "error" end)
