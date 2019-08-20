use Mix.Config

config :logger,
  # utc_log: true,
  truncate: :infinity,
  # backends: [:console],
  compile_time_purge_matching: [
    [module: Gelfx]
  ]

config :logger, Gelfx, port: 22_000
