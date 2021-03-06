defmodule TODO do
  @moduledoc File.read!(__DIR__ <> "/../README.md")

  def config_default(:persist), do: false
  def config_default(:print), do: :overdue

  def config(key) do
    case Application.get_env(:todo, key) do
      nil -> config_default(key)
      x -> x
    end
  end

  def validate_print_conf(nil), do: :ok
  def validate_print_conf(:all), do: :ok
  def validate_print_conf(:overdue), do: :ok
  def validate_print_conf(:silent), do: :ok

  def validate_print_conf(value) do
    raise "Bad print configuration value #{inspect(value)}."
  end

  defmacro __using__(opts) do
    # anything that is not false result in persisting = true. default is false
    print_conf = Keyword.get(opts, :print, config(:print))
    persist_conf = false !== Keyword.get(opts, :persist, config(:persist))
    validate_print_conf(print_conf)

    quote do
      Module.register_attribute(__MODULE__, :todo,
        accumulate: true,
        persist: unquote(persist_conf)
      )

      @before_compile unquote(__MODULE__)
      @todo_version Mix.Project.config()[:version]
      @todo_print_conf unquote(print_conf)

      defmacrop todo(items) do
        # TODO.print_todos(__MODULE__, items, @todo_version, @todo_print_conf)
        Module.put_attribute(__MODULE__, :todo, items)
      end
    end
  end

  defmacro __before_compile__(env) do
    app_version = Module.get_attribute(env.module, :todo_version)
    print_conf = Module.get_attribute(env.module, :todo_print_conf)

    if print_conf !== :silent do
      Module.get_attribute(env.module, :todo)
      |> output_todos(env.module, app_version, print_conf)
    end
  end

  def output_todos(_, _, _, :silent), do: :ok

  def output_todos(todos, module, app_version, print_conf) do
    case todos do
      [] ->
        nil

      nil ->
        nil

      items ->
        [items]
        |> List.flatten()
        |> Enum.map(&wrap_unversionned/1)
        |> Enum.sort(&sort_todos/2)
        |> Enum.reduce([], &group_todos/2)
        |> Enum.map(fn {version, ts} -> {version, ts} end)
        |> Enum.reverse()
        |> format_todos(app_version, print_conf)
        |> (fn x -> [format_module(module), x] end).()
        |> IO.puts()
    end
  end

  # put unversionned last
  def wrap_unversionned(x = {_version, _message}), do: x
  def wrap_unversionned(message), do: {:any, message}

  def sort_todos({_, _}, {:any, _}), do: true
  def sort_todos({:any, _}, {_, _}), do: false
  def sort_todos({v1, _}, {v2, _}), do: v1 < v2

  def group_todos({same_version, t}, [{same_version, ts} | rest]) do
    result = [{same_version, [t | ts]} | rest]
    result
  end

  def group_todos(item, {version, t}) do
    # first accumulator is not a list, it's a todo item, wrap and redo
    group_todos(item, [{version, [t]}])
  end

  def group_todos({version, t}, rest) do
    [{version, [t]} | rest]
  end

  def format_todos([], _, _) do
    []
  end

  def format_todos([{version, ts} | rest], app_version, print_conf) do
    current =
      case display_mode(version, app_version, print_conf) do
        :ignore -> []
        :info -> [format_version(version), format_messages(ts)]
        :warn -> IO.ANSI.format(yellow([format_version(version), format_messages(ts)]))
      end

    [current | format_todos(rest, app_version, print_conf)]
  end

  def format_module(atom) do
    ["@todos in ", to_string(atom)]
  end

  def format_version(:any) do
    format_version("No version")
  end

  def format_version(version) do
    ["\n * ", to_string(version), " :"]
  end

  def format_messages([message | []]) do
    # A single message => same line
    [" ", message]
  end

  def format_messages(messages) do
    Enum.map(messages, &["\n    - ", &1])
  end

  def display_mode(_, _, :silent), do: :ignore
  def display_mode(:any, _, _), do: :info

  def display_mode(version, app_version, print_conf) do
    version = to_string(version)

    case {Version.compare(version, app_version), print_conf} do
      {:gt, :all} ->
        # Version when the feature is required is greater than the current
        # version, it's not overdue, but we're asked to print all.
        :info

      {:gt, :overdue} ->
        # Same case, but we must print only overdue items, so no-print
        :ignore

      _ ->
        # App version is higher than feature version. The feature is due for a
        # past version. This is not good.
        :warn
    end
  end

  defp yellow(message) do
    [:yellow, message]
  end
end
