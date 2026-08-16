defmodule Thunk.Scheduler.Local do
  @moduledoc """
  Solves the two halves of a piece concurrently on the local node: the
  right half in a new linked process, the left half in the current one.
  Because the processes are linked, a crash in any piece brings down the
  whole job instead of leaving a caller waiting forever.

  This scheduler exists to exercise the piece representation across
  process boundaries before any networking is written. It does not
  bound the number of processes; that is the predicate's job.
  """

  @behaviour Thunk.Scheduler

  alias Thunk.Scheduler

  @impl true
  def solve(work, ctx) do
    if Scheduler.base?(work, ctx) do
      Scheduler.base(work, ctx)
    else
      {left, right} = Scheduler.split(work, ctx)
      right_task = Task.async(fn -> solve(right, ctx) end)
      left_result = solve(left, ctx)
      Scheduler.merge(work, left_result, Task.await(right_task, :infinity), ctx)
    end
  end
end
