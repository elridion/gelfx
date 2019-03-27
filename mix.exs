defmodule Gelfx.MixProject do
  use Mix.Project

  @version "0.1.4"

  def project do
    [
      app: :gelfx,
      version: @version,
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.1", only: :dev},
      {:ex_doc, "~> 0.19", only: :dev}
    ]
  end

  defp description() do
    "Elixir logger backend for Graylog based on GELF"
  end

  defp docs do
    [
      main: "Gelfx",
      canonical: "http://hexdocs.pm/gelfx",
      # logo: "guides/images/e.png",
      source_url: "https://github.com/elridion/gelfx"
    ]
  end

  defp package() do
    [
      maintainers: ["Hans Gödeke"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      licenses: ["Apache 2.0"],
      links: %{
        "GitHub" => "https://github.com/elridion/gelfx",
        "Graylog" => "https://www.graylog.org/"
      }
    ]
  end
end
