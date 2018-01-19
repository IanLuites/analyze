defmodule Analyze do
  @moduledoc ~S"""
  Documentation for Analyze.
  """

  alias Analyze.BuildStatus
  alias Analyze.CLI

  @methods %{
    "coverage" => {&Analyze.coverage/1, "Code Coverage", "Running code coverage...", []},
    "credo" => {&Analyze.credo/1, "Credo", "Checking code consistency...", ["--strict"]},
    "dialyzer" => {&Analyze.dialyzer/1, "Dialyzer", "Performing static analysis...", []},
    "format" => {&Analyze.format/1, "Code Formatting", "Checking code formatting...", []},
    "inch" => {&Analyze.inch/1, "Documentation", "Checking documentation quality...", []},
    "unit" => {&Analyze.unit/1, "Unit Tests", "Running unit tests...", []}
  }

  @default_analysis ~w(credo dialyzer coverage format)
  @full_analysis @default_analysis ++ ~w(inch)

  @task_timeout 10 * 60 * 1000

  def generate_config do
    execute("mix", ["credo", "gen.config"])
  end

  def main(options \\ [])

  def main([]) do
    analyze(@default_analysis, [])
  end

  def main(["full" | options]) do
    @full_analysis
    |> get_methods(options)
    |> analyze(options)
  end

  def main(options) do
    @default_analysis
    |> get_methods(options)
    |> analyze(options)
  end

  defp get_methods(methods, options) do
    filter =
      options
      |> Enum.filter(&String.starts_with?(&1, "--no-"))
      |> Enum.map(&String.trim_leading(&1, "--no-"))

    methods -- filter
  end

  defp analyze(methods, options) when is_list(methods) do
    case "coverage" in methods and !("unit" in methods) do
      true -> ["unit" | methods]
      false -> methods
    end
    |> Enum.map(&{&1, @methods |> Map.get(&1) |> elem(1)})
    |> CLI.start(!("--non-interactive" in options))

    case "--async-disabled" in options do
      true ->
        methods
        |> Enum.map(&analyze(&1, options))

      false ->
        methods
        |> Enum.map(fn method -> Task.async(fn -> analyze(method, options) end) end)
        |> Enum.map(&Task.await(&1, @task_timeout))
    end
    |> List.flatten()
    |> CLI.stop()
  end

  defp analyze(method, options) do
    case Map.get(@methods, method) do
      nil -> :ok
      data -> run_analysis(method, data, options)
    end
  end

  defp run_analysis(method, {function, label, description, default_args}, options) do
    report = "--report" in options

    filtered_options =
      options
      |> Enum.filter(&String.starts_with?(&1, "--" <> method))
      |> Enum.map(&String.trim_leading(&1, "--" <> method))

    filtered_options =
      case filtered_options do
        [] -> default_args
        filtered_options -> filtered_options
      end

    filtered_options =
      case method == "coverage" && report do
        true -> ["--report"]
        false -> filtered_options
      end

    if report, do: BuildStatus.report(method, "INPROGRESS", label, description)

    case function.(filtered_options) do
      {:ok, status, _output, sub} ->
        if report, do: BuildStatus.report(method, "SUCCESSFUL", label, status)

        CLI.passed(method)

        [{:ok, label} | sub]

      {:error, status, output, sub} ->
        if report, do: BuildStatus.report(method, "FAILED", label, status)

        CLI.failed(method)

        [{:error, label, output} | sub]
    end
  end

  def credo(options) do
    {output, status} = execute("mix", ["credo"] ++ options)

    short =
      output
      |> String.split("\n")
      |> Enum.take(-3)
      |> List.first()
      |> String.replace(~r/\x1b\[[0-9;]*m/, "")

    case status do
      0 -> {:ok, short, output, []}
      _ -> {:error, short, output, []}
    end
  end

  def dialyzer(options) do
    {output, status} = execute("mix", ["dialyzer", "--halt-exit-status"] ++ options)

    [_, time] =
      ~r/done in ([0-9]+m[0-9\.]+s)/
      |> Regex.run(output)

    case status do
      0 -> {:ok, "Passed (#{time})", output, []}
      _ -> {:error, "Failed (#{time})", output, []}
    end
  end

  def format(_options) do
    {output, status} = execute("mix", ["format", "--check-formatted"])

    count = output |> String.split(~r/\r?\n/) |> Enum.count() |> Kernel.-(5)

    case status do
      0 -> {:ok, "All files are properly formatted.", "All files are properly formatted.", []}
      _ -> {:error, "#{count} files need formatting.", output, []}
    end
  end

  def coverage(options) do
    report = "--report" in options

    options =
      case report do
        true -> List.delete(options, "--report")
        false -> options
      end

    # Report, because unit == coverage
    {_, unit_label, unit_description, _} = Map.get(@methods, "unit")
    if report, do: BuildStatus.report("unit", "INPROGRESS", unit_label, unit_description)

    {output, _status} = execute("mix", ["test", "--cover"] ++ options)

    clean = output |> String.replace(~r/\x1b\[[0-9;]*m/, "")
    {message, _, failure} = test_count(clean)

    # Report, because unit == coverage
    unit =
      if failure == 0 do
        if report, do: BuildStatus.report("unit", "SUCCESSFUL", unit_label, message)

        CLI.passed("unit")
        []
      else
        if report, do: BuildStatus.report("unit", "FAILED", unit_label, message)

        CLI.failed("unit")
        [{:error, "unit", output}]
      end

    percentage =
      ~r/\[TOTAL\]\ *([0-9\.]+)%/
      |> Regex.run(clean)

    case percentage do
      nil ->
        {:error, "Could not run code coverage.", output, unit}

      percentage ->
        percentage =
          percentage
          |> List.last()
          |> String.to_float()

        case percentage < 100 do
          true -> {:error, "#{percentage}% code coverage.", output, unit}
          false -> {:ok, "#{percentage}% code coverage.", output, unit}
        end
    end
  end

  def unit(options) do
    {output, status} = execute("mix", ["test"] ++ options)

    clean = output |> String.replace(~r/\x1b\[[0-9;]*m/, "")
    {message, _, _} = test_count(clean)

    case status do
      0 -> {:ok, message, output, []}
      _ -> {:error, message, output, []}
    end
  end

  defp test_count(output) do
    tests_output =
      ~r/(Finished in [0-9\.]+ seconds)\r?\n([0-9]+ tests?, [0-9]+ failures?)/
      |> Regex.run(output)

    case tests_output do
      [_, time, tests] ->
        [_, total, failed] =
          ~r/([0-9]+) tests?, ([0-9]+) failures?/
          |> Regex.run(tests)

        {"#{tests} (#{time})", String.to_integer(total), String.to_integer(failed)}

      _ ->
        {"Unit tests failed", 0, 1}
    end
  end

  def inch(options) do
    {output, _status} = execute("mix", ["inch"] ++ options)

    clean = output |> String.replace(~r/\x1b\[[0-9;]*m/, "")

    look_at_count =
      case String.contains?(clean, "Nothing to suggest.") do
        true ->
          0

        false ->
          ~r/You might want to look at these files:(.*?)Grade distribution/s
          |> Regex.run(clean)
          |> List.last()
          |> String.split("\n")
          |> Enum.count()
          |> Kernel.-(4)
      end

    case look_at_count do
      0 -> {:ok, "Well documented.", output, []}
      _ -> {:error, "#{look_at_count} files to document.", output, []}
    end
  end

  @spec execute(String.t(), [String.t()]) :: {String.t(), integer}
  defp execute(command, options) do
    case :os.type() do
      {:unix, :darwin} ->
        commands = ["-q", "/dev/null", command] ++ options

        System.cmd("script", commands)

      {:unix, _} ->
        System.cmd(command, options, stderr_to_stdout: true)
    end
  end
end
