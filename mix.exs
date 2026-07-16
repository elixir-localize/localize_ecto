defmodule LocalizeEcto.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/elixir-localize/localize_ecto"

  def project do
    [
      app: :localize_ecto,
      version: @version,
      name: "Localize Ecto",
      source_url: @source_url,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  def description do
    "Locale-aware PostgreSQL ICU collation for Ecto queries: COLLATE query expressions " <>
      "resolved from Localize language tags, and migration helpers for creating collations."
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Readme" => "#{@source_url}/blob/v#{@version}/README.md",
        "Changelog" => "#{@source_url}/blob/v#{@version}/CHANGELOG.md"
      },
      files: [
        "lib",
        "priv",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
      ]
    ]
  end

  def docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/using_localize_ecto.md",
        "guides/collations_in_postgres.md",
        "CHANGELOG.md",
        "LICENSE.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp deps do
    [
      {:ecto, "~> 3.12"},
      {:localize, "~> 0.50"},
      {:ecto_sql, "~> 3.12", optional: true},
      {:postgrex, "~> 0.20", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: [:dev, :release], runtime: false}
    ]
  end
end
