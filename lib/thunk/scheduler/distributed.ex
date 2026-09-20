defmodule Thunk.Scheduler.Distributed do
  @moduledoc """
  Work stealing across peers. Solving a piece pushes its right half to
  the local worker's deque, solves the left half in this process, then
  takes the right half back if nobody wanted it, or waits for the
  result from whoever stole it.

  A stolen piece is evaluated by run_piece/1 on the thief: it fetches
  the job's definitions if it does not have them, solves the piece with
  this same scheduler (so it can be split and stolen further), and sends
  the value back to the owner.

  Failures travel by monitor. The owner watches the thief's worker until
  it learns which evaluator has the piece, then that evaluator. If either
  dies because of a language error the owner re-raises that error, since
  the program is deterministic and would fail again. If it dies for any
  other reason, a crashed process or a lost node, the owner solves the
  piece again itself: it is pure, so the result is the same.
  """

  @behaviour Thunk.Scheduler

  require Logger

  alias Thunk.{Context, Error, Piece, Scheduler, Worker}

  @impl true
  def solve(work, ctx) do
    if Scheduler.base?(work, ctx) do
      Scheduler.base(work, ctx)
    else
      {left, right} = Scheduler.split(work, ctx)
      ref = make_ref()
      Worker.push(%Piece{work: right, ref: ref, reply_to: self(), job: ctx.job})

      {left_result, right_result} =
        try do
          left_result = solve(left, ctx)

          right_result =
            case Worker.take_back(ref) do
              {:ok, piece} ->
                solve(piece.work, ctx)

              {:stolen, thief} ->
                case await(ref, thief) do
                  {:ok, value} ->
                    value

                  {:lost, reason} ->
                    # A lost piece can be recomputed because the work is pure.
                    Logger.warning(
                      "piece #{inspect(ref)} lost (#{inspect(reason)}), solving it again"
                    )

                    Worker.recovered()
                    solve(right, ctx)
                end

              {:error, :unknown} ->
                raise Error, "piece #{inspect(ref)} vanished from the deque"
            end

          {left_result, right_result}
        rescue
          error ->
            # Don't leave this piece in the deque after an error.
            Worker.take_back(ref)
            reraise error, __STACKTRACE__
        end

      Scheduler.merge(work, left_result, right_result, ctx)
    end
  end

  @doc """
  Evaluates a stolen piece and sends the result to its owner. Runs in an
  evaluator process started by the worker.
  """
  @spec run_piece(Piece.t()) :: :ok
  def run_piece(%Piece{} = piece) do
    ctx = job_context(piece.job)
    value = solve(piece.work, ctx)
    send(piece.reply_to, {:result, piece.ref, value})
    :ok
  end

  defp job_context(job) do
    case Worker.job_context(job) do
      {:ok, ctx} ->
        ctx

      :unknown ->
        {id, origin} = job
        {:ok, defs} = Worker.fetch_job(origin, id)
        Worker.register_job(id, defs)
        %Context{defs: defs, scheduler: __MODULE__, job: job}
    end
  end

  defp await(ref, thief) do
    mon = Process.monitor(thief)

    receive do
      {:result, ^ref, value} ->
        Process.demonitor(mon, [:flush])
        flush_claimed(ref)
        {:ok, value}

      {:claimed, ^ref, evaluator} ->
        Process.demonitor(mon, [:flush])
        await_result(ref, Process.monitor(evaluator))

      {:failed, ^ref, reason} ->
        Process.demonitor(mon, [:flush])
        lost(reason)

      {:DOWN, ^mon, :process, _pid, reason} ->
        lost(reason)
    end
  end

  # The worker reports evaluator failures; the monitor catches node loss.
  defp await_result(ref, mon) do
    receive do
      {:result, ^ref, value} ->
        Process.demonitor(mon, [:flush])
        {:ok, value}

      {:failed, ^ref, reason} ->
        Process.demonitor(mon, [:flush])
        lost(reason)

      {:DOWN, ^mon, :process, _pid, reason} ->
        lost(reason)
    end
  end

  # Result and claim come from different processes and can arrive out of order.
  defp flush_claimed(ref) do
    receive do
      {:claimed, ^ref, _} -> :ok
    after
      0 -> :ok
    end
  end

  defp lost({%Error{} = error, _stacktrace}), do: raise(error)
  defp lost(reason), do: {:lost, reason}
end
