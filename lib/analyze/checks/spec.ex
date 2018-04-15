defmodule Analyze.Checks.Spec do
  @types [:spec, :impl]

  def title, do: "Spec Check"
  def description, do: "Checking spec and behavior quality..."

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
      {:ok, "Spec and behaviors looking good.", "", []}
    else
      {:error, "#{error_count} spec and behavior errors.",
       report
       |> Tidy.errors(type: @types)
       |> String.replace(~r/\x1b\[[0-9;]*m/, ""), []}
    end
  end
end
