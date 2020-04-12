defmodule Analyze do
  @moduledoc ~S"""
  Documentation for Analyze.
  """

  alias Analyze.BuildStatus
  alias Analyze.CLI
  alias Analyze.Checks.{Spec, Documentation}

  @methods %{
    "coverage" => {&Analyze.coverage/1, "Code Coverage", "Running code coverage...", []},
    "credo" => {&Analyze.credo/1, "Credo", "Checking code consistency...", ["--strict"]},
    "dialyzer" => {&Analyze.dialyzer/1, "Dialyzer", "Performing static analysis...", []},
    "doc" => {&Documentation.run/1, Documentation.title(), Documentation.description(), []},
    "format" => {&Analyze.format/1, "Code Formatting", "Checking code formatting...", []},
    "spec" => {&Spec.run/1, Spec.title(), Spec.description(), []},
    "unit" => {&Analyze.unit/1, "Unit Tests", "Running unit tests...", []},
    "security" =>
      {&Analyze.security/1, "Security Checks", "Running security checks...",
       ["--exit", "--private", "--skip"]}
  }

  @default_analysis ~w(credo dialyzer coverage format doc spec security)
  @full_analysis @default_analysis ++ ~w()

  @task_timeout 10 * 60 * 1000

  defp phoenix?,
    do:
      :application.ensure_started(:phoenix) !=
        {:error, {'no such file or directory', 'phoenix.app'}}

  def generate_config do
    execute("mix", ["credo", "gen.config"])
  end

  def main(options \\ [])

  def main([]) do
    default = if phoenix?(), do: @default_analysis, else: @default_analysis -- ["security"]

    analyze(default, [])
  end

  def main(["full" | options]) do
    @full_analysis
    |> get_methods(options)
    |> analyze(options)
  end

  def main(options) do
    default = if phoenix?(), do: @default_analysis, else: @default_analysis -- ["security"]

    default
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

  defp configure([]), do: :ok

  defp configure(["--build-url", url | rest]) do
    Application.put_env(:analyze, :status_build_url, url)
    configure(rest)
  end

  defp configure(["--status-auth", auth | rest]) do
    Application.put_env(:analyze, :status_authorization, auth)
    configure(rest)
  end

  defp configure(["--status-refresh-token", id, token | rest]) do
    Application.put_env(:analyze, :status_refresh_token, {id, token})
    configure(rest)
  end

  defp configure(["--status-endpoint", endpoint | rest]) do
    Application.put_env(:analyze, :status_endpoint, endpoint)
    configure(rest)
  end

  defp configure(["--timeout", timeout | rest]) do
    Application.put_env(:analyze, :timeout, String.to_integer(timeout) * 1_000)
    configure(rest)
  end

  defp configure([_ | rest]), do: configure(rest)

  defp analyze(methods, options) when is_list(methods) do
    configure(options)
    Mix.Task.run("compile")

    case "coverage" in methods and !("unit" in methods) do
      true -> ["unit" | methods]
      false -> methods
    end
    |> Enum.map(&{&1, @methods |> Map.get(&1) |> elem(1)})
    |> CLI.start(!("--non-interactive" in options))

    task_timeout = Application.get_env(:analyze, :timeout, @task_timeout)

    case "--async-disabled" in options do
      true ->
        methods
        |> Enum.map(&analyze(&1, options))

      false ->
        methods
        |> Enum.map(fn method -> {method, Task.async(fn -> analyze(method, options) end)} end)
        |> Enum.map(fn {m, t} -> await(m, t, task_timeout) end)
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

  defp await(method, task, timeout) do
    Task.await(task, timeout)
  catch
    :exit, _ ->
      {_, method, _, _} = Map.get(@methods, method)

      CLI.failed(method)
      {:error, method, "Timed out after: #{timeout}ms"}
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
    [_, time] = Regex.run(~r/done in ([0-9]+m[0-9\.]+s)/, output) || ["???", "???"]

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

  def security(options) do
    {output, status} = execute("mix", ["sobelow"] ++ options)

    short =
      "#{~r/^File\: / |> Regex.scan(output) |> Enum.count()} potential security issues found."

    case status do
      0 -> {:ok, short, output, []}
      _ -> {:error, short, output, []}
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

    {format, options} =
      Enum.find_value(options, {["test", "--cover"], options}, fn
        "-format=" <> format -> {["coveralls.#{format}"], options -- ["-format=" <> format]}
        _ -> nil
      end)

    {output, _status} = execute("mix", format ++ options)

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

  def test_count(output) do
    captures =
      ~r/Finished in (?<time>[0-9\.])+ seconds\r?\n((?<doctests>[0-9]+) doctests, )?((?<tests>[0-9]+) tests?, )?(?<failures>[0-9]+) failures?/
      |> Regex.named_captures(output)

    case captures do
      %{"failures" => failed, "time" => time} ->
        tests =
          String.to_integer("0" <> captures["tests"]) +
            String.to_integer("0" <> captures["doctests"])

        {"#{tests} (#{time} seconds)", tests, String.to_integer(failed)}

      _ ->
        {"Unit tests failed", 0, 1}
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
