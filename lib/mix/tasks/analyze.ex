defmodule Mix.Tasks.Analyze do
  use Mix.Task

  @shortdoc  "Run code analysis (use `--help` for options)"
  @moduledoc @shortdoc

  @doc false
  def run(argv) do
    {:ok, _started} = Application.ensure_all_started(:hackney)

    Analyze.main(argv)
  end
end
