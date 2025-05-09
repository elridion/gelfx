import Config

config :logger, Gelfx, port: 22_000

config :logger,
  # utc_log: true,
  truncate: :infinity,
  # backends: [:console],
  compile_time_purge_matching: [
    [module: Gelfx]
  ]
