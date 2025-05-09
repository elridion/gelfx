import Config

config :logger, Gelfx,
  host: "localhost",
  port: 12_201,
  protocol: :tcp,
  level: :info

config :logger,
  truncate: :infinity,
  backends: [
    :console,
    Gelfx
  ]

# host: "190.0.0.1",
