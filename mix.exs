defmodule LocalizeEcto.MixProject do
  use Mix.Project

  def project do
    [
      app: :localize_ecto,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:ecto, "~> 3.12"},
      {:localize, "~> 0.50"},
      {:ecto_sql, "~> 3.12", only: [:dev, :test]},
      {:postgrex, "~> 0.20", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: [:dev, :release], runtime: false}
    ]
  end
end
