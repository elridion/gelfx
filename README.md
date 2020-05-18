# Gelfx
Elixir logger backend for Graylog based on GELF.
Documentation is available on [hex.pm](https://hexdocs.pm/gelfx)

<a href="https://frobese.io/" target="_blank"><img src="images/banner-frobeseio.png" alt="frobese.io logo" width="250"/></a>

## Installation
The package can be installed by adding `gelfx` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gelfx, "~> 1.0"}
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
```elixir
    {:jason, "~> 1.0"}
``` 
## Features
Gelfx has full support of the Elixir Logger and Gelf/Graylog features.

- Support for __TCP__, __UDP__, and __HTTP__
- Graceful changes to the protocol configuration during runtime
- Support for __GZIP__ and __ZLIB__ compression
- __(TCP)__ When Gelfx is unable to transmit packets due to an connection loss packets are stored and resend once the connection is reestablished
- Log-levels are correctly mapped onto the corresponding GELF selectors
- Elixir `format` - Log messages are formatted using the [`Elixir.Logger.Formatter`](https://hexdocs.pm/logger/Logger.Formatter.html)
- Logger`metadata` is correctly the GELF payload
- Support for the `utc_log` Logger option, since GELF expects utc timestamps this has to be handled accordingly

## Copyright and License
Copyright 2020 Hans Bernhard Gödeke

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.