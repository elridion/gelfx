# Gelfx
Documentation is available on [hex.pm](https://hexdocs.pm/gelfx)  
The package can be installed by adding `gelfx` to your list of dependencies in `mix.exs`:

 ```elixir
  def deps do
    [
      {:gelfx, "~> 0.1.0"}
    ]
  end
  ```
  And adding it to your `:logger` configuration in `config.exs`:
  ```elixir
  config :logger,
    backends: [
      :console,
      Gelfx
    ]
  ```
  Since GELF relies on json to encode the payload Gelfx will need a JSON library. By default Gelfx will use Jason which needs to be added to your deps in mix.exs:

      {:jason, "~> 1.0"}
