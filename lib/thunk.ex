defmodule Thunk do
  @moduledoc """
  Thunk evaluates pure computations written in a small functional
  language. A program is a sequence of top-level definitions; running it
  applies the definition called main to an input value.

      ctx = Thunk.Prelude.load()
      ctx = Thunk.load("def main(xs) = length(xs)", ctx)
      Thunk.run(ctx, [1, 2, 3])

  The scheduler in the context decides how divide-and-conquer work is
  evaluated: sequentially, on local processes, or, later, on other nodes.
  """

  alias Thunk.{Context, Error, Eval, Parser}

  @doc """
  Evaluates every def in `source`, in order, adding it to the context.
  """
  @spec load(String.t(), Context.t()) :: Context.t()
  def load(source, %Context{} = ctx \\ %Context{}) do
    Enum.reduce(Parser.parse!(source), ctx, fn
      [:def, name, expr], ctx when is_atom(name) ->
        %{ctx | defs: Map.put(ctx.defs, name, Eval.eval(expr, %{}, ctx))}

      other, _ctx ->
        raise Error, "expected a def at top level, got #{inspect(other)}"
    end)
  end

  @doc """
  Applies the definition called main to `input`.
  """
  @spec run(Context.t(), term) :: term
  def run(%Context{defs: %{main: main}} = ctx, input), do: Eval.apply(main, [input], ctx)
  def run(%Context{}, _input), do: raise(Error, "program has no main")

  @doc """
  Evaluates a single expression. `env` binds symbols to values built on
  the Elixir side, which is convenient for tests and experiments.
  """
  @spec eval(String.t(), Context.t(), map) :: term
  def eval(source, %Context{} = ctx \\ %Context{}, env \\ %{}) do
    case Parser.parse!(source) do
      [form] -> Eval.eval(form, env, ctx)
      _ -> raise Error, "expected exactly one expression"
    end
  end

  @spec with_scheduler(Context.t(), module) :: Context.t()
  def with_scheduler(%Context{} = ctx, scheduler), do: %{ctx | scheduler: scheduler}
end
