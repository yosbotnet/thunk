defmodule Thunk.MembershipTest do
  use ExUnit.Case, async: false

  @moduletag :distributed
  @moduletag :capture_log
  @moduletag timeout: 120_000

  alias Thunk.{Cluster, TestCluster, Worker}
  alias Thunk.Scheduler.Sequential

  # No transitive mesh from the BEAM: every connection a peer has is one
  # it made itself, from its seeds or from the member lists it received.
  @no_mesh [~c"-connect_all", ~c"false"]

  setup do
    %{limit: limit} = Worker.stats()
    on_exit(fn -> Worker.set_limit(limit) end)
    :ok
  end

  test "nodes that know only one seed end up knowing each other" do
    a = start(:ma, seeds: [])
    b = start(:mb, seeds: [TestCluster.peer_node(a)])
    c = start(:mc, seeds: [TestCluster.peer_node(b)])
    nodes = Enum.map([a, b, c], &TestCluster.peer_node/1)

    for pid <- [a, b, c] do
      assert eventually(fn -> nodes -- members(pid) == [] end),
             "#{TestCluster.peer_node(pid)} knows only #{inspect(members(pid))}"
    end

    # a and c never had each other as seed, but are now connected directly
    assert TestCluster.peer_node(c) in :peer.call(a, Node, :list, [])
  end

  test "a node that joins while a job runs takes part in it" do
    # The test node evaluates nothing itself, so the pieces go to the
    # peers: first only a, then also the node that joins through a.
    Worker.set_limit(0)
    a = start(:ja, seeds: [node()])
    :ok = Cluster.wait_for_peers(1, 10_000)

    program = """
    def spin(n) = if n == 0 then 0 else spin(n - 1)
    def main(xs) =
      dc(xs, fn(v) -> length(v) < 4, halves,
         fn(v) -> let z = spin(300000) in v,
         append)
    """

    ctx = Cluster.load(program)
    # long enough that the joiner, which takes about a second to boot,
    # finds the job still running
    xs = Enum.to_list(1..256)
    job = Task.async(fn -> Cluster.run(ctx, xs) end)

    Process.sleep(300)
    joiner = start(:jb, seeds: [TestCluster.peer_node(a)])

    assert Task.await(job, 60_000) == Thunk.run(Thunk.with_scheduler(ctx, Sequential), xs)

    stats = Worker.stats(TestCluster.peer_node(joiner))
    assert stats.steals + stats.evaluated > 0
    assert node() in members(joiner)
  end

  defp start(name, opts) do
    pid = TestCluster.start_peer(name, [args: @no_mesh] ++ opts)
    on_exit(fn -> TestCluster.stop_peer(pid) end)
    pid
  end

  defp members(pid), do: :peer.call(pid, Cluster, :members, [])

  defp eventually(fun, timeout \\ 10_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait(fun, deadline)
  end

  defp wait(fun, deadline) do
    cond do
      fun.() ->
        true

      System.monotonic_time(:millisecond) > deadline ->
        false

      true ->
        Process.sleep(100)
        wait(fun, deadline)
    end
  end
end
