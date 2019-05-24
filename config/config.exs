use Mix.Config

config :logger, Gelfx,
  host: "localhost",
  port: 12_201,
  protocol: :tcp

import_config "#{Mix.env()}.exs"
