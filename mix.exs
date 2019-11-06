defmodule Analyze.Mixfile do
  use Mix.Project

  def project do
    [
      app: :analyze,
      description: "Mix task to analyze and report Elixir code.",
      # escript: [main_module: Analyze],
      version: "0.1.6",
      elixir: "~> 1.7",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],

      # Docs
      name: "Analyze",
      source_url: "https://github.com/IanLuites/analyze",
      homepage_url: "https://github.com/IanLuites/analyze",
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  def package do
    [
      name: :analyze,
      maintainers: ["Ian Luites"],
      licenses: ["MIT"],
      files: [
        # Elixir
        "lib/analyze",
        "lib/mix",
        "lib/analyze.ex",
        "mix.exs",
        "README*",
        "LICENSE*"
      ],
      links: %{
        "GitHub" => "https://github.com/IanLuites/analyze"
      }
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:hackney, "~> 1.15"},
      {:jason, "~> 1.1"},

      # Code Tools
      {:credo, ">= 1.1.5", runtime: false},
      {:dialyxir, ">= 1.0.0-rc.7", only: [:dev], runtime: false, optional: true},
      {:ex_doc, ">= 0.20.2"},
      {:excoveralls, ">= 0.12.0"},
      {:tidy, ">= 0.1.0"}
    ]
  end
end
