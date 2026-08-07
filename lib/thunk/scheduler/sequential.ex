defmodule Thunk.Scheduler.Sequential do
  @moduledoc """
  Solves a piece by plain recursion in the calling process. This is the
  reference implementation: every other scheduler must give the same
  result.
  """

  @behaviour Thunk.Scheduler

  alias Thunk.Scheduler

  @impl true
  def solve(work, ctx) do
    if Scheduler.base?(work, ctx) do
      Scheduler.base(work, ctx)
    else
      {left, right} = Scheduler.split(work, ctx)
      Scheduler.merge(work, solve(left, ctx), solve(right, ctx), ctx)
    end
  end
end
