defmodule Thunk.Scheduler do
  @moduledoc """
  A scheduler decides where and in what order the pieces of a dc are
  solved. The result never depends on that choice, only on the four
  functions in the piece.

  The helpers below apply those functions through the evaluator and
  check their contracts, so every scheduler shares the same semantics.
  """

  alias Thunk.{Context, Error, Eval, Work}

  @callback solve(Work.t(), Context.t()) :: term

  @spec base?(Work.t(), Context.t()) :: boolean
  def base?(%Work{pred: pred, value: value}, ctx) do
    case Eval.apply(pred, [value], ctx) do
      result when is_boolean(result) -> result
      other -> raise Error, "dc predicate returned #{inspect(other)}, expected a boolean"
    end
  end

  @spec base(Work.t(), Context.t()) :: term
  def base(%Work{base: base, value: value}, ctx), do: Eval.apply(base, [value], ctx)

  @spec split(Work.t(), Context.t()) :: {Work.t(), Work.t()}
  def split(%Work{split: split, value: value} = work, ctx) do
    case Eval.apply(split, [value], ctx) do
      [left, right] -> {%{work | value: left}, %{work | value: right}}
      other -> raise Error, "dc split returned #{inspect(other)}, expected a list of two values"
    end
  end

  @spec merge(Work.t(), term, term, Context.t()) :: term
  def merge(%Work{merge: merge}, left, right, ctx), do: Eval.apply(merge, [left, right], ctx)
end
