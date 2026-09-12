defmodule Thunk.Cluster do
  @moduledoc """
  Submitting jobs to the cluster from this node.

  load/1 parses a program on top of the prelude, registers its
  definitions on the local worker under a fresh job id, and returns a
  context whose scheduler is the distributed one. run/2 then evaluates
  main in the calling process, which becomes the root of the job's tree.
  Any node can do this; there is no designated coordinator.
  """

  alias Thunk.{Context, Worker}
  alias Thunk.Scheduler.Distributed

  @spec load(String.t()) :: Context.t()
  def load(source) do
    ctx = Thunk.load(source, Worker.prelude())
    id = make_ref()
    :ok = Worker.register_job(id, ctx.defs)
    %{ctx | scheduler: Distributed, job: {id, node()}}
  end

  @spec run(Context.t(), term) :: term
  def run(%Context{} = ctx, input), do: Thunk.run(ctx, input)

  @doc "Connects to the given nodes, returning those that could be reached."
  @spec connect([node]) :: [node]
  def connect(nodes), do: Enum.filter(nodes, &(Node.connect(&1) == true))

  @doc "Waits until at least `count` other nodes are connected."
  @spec wait_for_peers(non_neg_integer, non_neg_integer) :: :ok | :timeout
  def wait_for_peers(count, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait(count, deadline)
  end

  defp do_wait(count, deadline) do
    cond do
      length(Node.list()) >= count ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        :timeout

      true ->
        Process.sleep(100)
        do_wait(count, deadline)
    end
  end
end
