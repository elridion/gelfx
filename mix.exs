defmodule Gelfx.MixProject do
  use Mix.Project

  @version "1.3.0"

  def project do
    [
      app: :gelfx,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def elixirc_paths(env) when env in [:dev, :test] do
    ["test/test_helper" | elixirc_paths(nil)]
  end

  def elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:logger_backends, "~> 1.0"},
      {:ex_doc, "~> 0.38.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18.5", only: :test},
      {:styler, "~> 1.0.0", only: [:dev, :test], runtime: false},
      {:eunomo, "~> 3.0.0", only: :dev}
    ]
  end

  defp description do
    "Elixir logger backend for Graylog based on GELF"
  end

  defp docs do
    [
      main: "Gelfx",
      canonical: "http://hexdocs.pm/gelfx",
      source_url: "https://github.com/elridion/gelfx"
    ]
  end

  defp package do
    [
      maintainers: ["Hans Gödeke"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/elridion/gelfx",
        "Graylog" => "https://www.graylog.org/"
      }
    ]
  end
end
