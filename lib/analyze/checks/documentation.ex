defmodule Analyze.Checks.Documentation do
  @types [:doc]

  def title, do: "Documentation Check"
  def description, do: "Checking documentation quality..."

  def run(_options) do
    app =
      ~r/app: *:(?<app>[a-z\_]+)/
      |> Regex.named_captures(File.read!("./mix.exs"))
      |> Map.get("app")
      |> String.to_existing_atom()

    Application.load(app)

    report = Tidy.analyze_app(app)
    error_count = Tidy.errors?(report, type: @types)

    if error_count <= 0 do
      {:ok, "Documentation looking good.", "", []}
    else
      {:error, "#{error_count} documentation errors.",
       report
       |> Tidy.errors(type: @types)
       |> String.replace(~r/\x1b\[[0-9;]*m/, ""), []}
    end
  end
end
