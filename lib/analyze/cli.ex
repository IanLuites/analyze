defmodule Analyze.CLI do
  @moduledoc ~S"""
  Analyze CLI.
  """

  use GenServer

  @ansi_cursor_hide "\e[?25l"
  @ansi_cursor_show "\e[?25h"
  @ansi_cursor_reset "\e[1000D"

  @ansi_clear_line "\e[K"

  @ui_refresh 100

  @spinner [
    "🕐 ",
    "🕑 ",
    "🕒 ",
    "🕓 ",
    "🕔 ",
    "🕕 ",
    "🕖 ",
    "🕗 ",
    "🕘 ",
    "🕙 ",
    "🕚 "
  ]
  @ansi_passed "\e[32m ✓\e[0m"
  @ansi_failed "\e[31m ✗\e[0m"
  # @ansi_passed "✅ "
  # @ansi_failed "❌ "
  # @ansi_passed "✅ "
  # @ansi_failed "🅾️ "

  def start(labels, interactive \\ true) do
    {:ok, _pid} = GenServer.start_link(__MODULE__, {labels, interactive}, name: __MODULE__)

    labels
  end

  def stop(results) do
    send(__MODULE__, {:stop, self()})

    results = Enum.reject(results, &(elem(&1, 0) == :ok))

    receive do
      :stopped -> true
    end

    IO.puts(@ansi_cursor_show <> @ansi_clear_line)

    if results != [] do
      # answer =
      #   "Want to see the output? [Y/n]"
      #   |> IO.gets
      #   |> String.downcase
      #   |> String.first

      # case answer do
      #   "n" -> :ok
      #   _ -> print_results(results)
      # end
      print_results(results)
    end

    if results == [] do
      System.halt(0)
    else
      System.halt(1)
    end
  end

  defp print_results(results) do
    results
    |> Enum.map(&print_errors/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\r\n\r\n")
    |> String.trim()
    |> IO.puts()
  end

  defp print_errors({:ok, _method}), do: :ok

  defp print_errors({:error, method, output}) do
    "\e[1m🚨  " <> method <> " 🚨 \e[0m\r\n" <> output
  end

  def passed(method) do
    send(__MODULE__, {:task_status, method, :passed})
  end

  def failed(method) do
    send(__MODULE__, {:task_status, method, :failed})
  end

  # GenServer

  def init({labels, interactive}) do
    tasks =
      labels
      |> Enum.map(fn {method, label} -> {method, label, :running} end)

    state = %{
      tasks: tasks,
      frame: 0
    }

    if interactive do
      Process.send_after(__MODULE__, :render, @ui_refresh)
      {:ok, setup_screen(state)}
    else
      IO.puts("Performing analysis:")
      {:ok, state}
    end
  end

  def handle_info(:render, state) do
    Process.send_after(__MODULE__, :render, @ui_refresh)
    {:noreply, render(state)}
  end

  def handle_info({:stop, pid}, state) do
    state = render(state)

    send(pid, :stopped)

    {:stop, :normal, state}
  end

  def handle_info({:task_status, method, status}, state = %{tasks: tasks}) do
    tasks =
      Enum.map(tasks, fn {task_method, label, task_status} ->
        case method == task_method do
          true -> {task_method, label, status}
          false -> {task_method, label, task_status}
        end
      end)

    {:noreply, %{state | tasks: tasks}}
  end

  # Render
  def setup_screen(state) do
    IO.write(@ansi_cursor_hide)

    IO.puts("Performing analysis:")

    render(state)
  end

  def render_task({_task, label, :running}, %{spinner: spinner}) do
    IO.puts("  #{spinner} " <> label)
  end

  def render_task({_task, label, :failed}, %{}) do
    IO.puts("  #{@ansi_failed} " <> label)
  end

  def render_task({_task, label, :passed}, %{}) do
    IO.puts("  #{@ansi_passed} " <> label)
  end

  def render(state = %{tasks: tasks, frame: frame}) do
    icons = %{
      spinner: animation_frame(@spinner, frame)
    }

    if frame != 0, do: tasks |> Enum.count() |> ansi_cursor_up()

    IO.write(@ansi_cursor_reset)
    Enum.each(tasks, &render_task(&1, icons))
    IO.write(@ansi_clear_line)

    %{state | frame: frame + 1}
  end

  defp animation_frame(animation, _frame) when is_binary(animation) do
    animation
  end

  defp animation_frame(animation, frame) when is_list(animation) do
    frame = rem(frame, Enum.count(animation))

    Enum.at(animation, frame)
  end

  defp ansi_cursor_up(lines, reset \\ true) do
    if reset, do: IO.write(@ansi_cursor_reset)
    IO.write("\e[#{lines}A")
  end
end
