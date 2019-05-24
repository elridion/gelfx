use Mix.Config

config :logger,
  truncate: :infinity,
  backends: [
    :console,
    Gelfx
  ]

config :logger, Gelfx,
  host: "localhost",
  # host: "190.0.0.1",
  port: 12_201,
  protocol: :tcp,
  level: :info
