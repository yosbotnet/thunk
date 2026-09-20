defmodule Thunk.ClusterTest do
  use ExUnit.Case, async: false

  @moduletag :distributed
  @moduletag :capture_log
  @moduletag timeout: 120_000

  alias Thunk.{Cluster, Error, TestCluster, Worker}
  alias Thunk.Scheduler.Sequential

  setup_all do
    peers = for name <- [:node2, :node3], do: TestCluster.start_peer(name)
    :ok = Cluster.wait_for_peers(2, 10_000)
    on_exit(fn -> Enum.each(peers, &TestCluster.stop_peer/1) end)
    %{peers: peers}
  end

  setup do
    # Force the peers to do the work.
    Worker.set_limit(0)
    :ok
  end

  test "mergesort across nodes equals the sequential result and pieces were stolen", %{
    peers: peers
  } do
    # Keep the job alive long enough for peers to steal.
    xs = Enum.shuffle(1..10_000)

    ctx =
      Cluster.load("(def main (lambda (xs) (mergesort xs (lambda (v) (lt (length v) 50)))))")

    assert Cluster.run(ctx, xs) == Thunk.run(Thunk.with_scheduler(ctx, Sequential), xs)

    steals = for p <- peers, do: Worker.stats(TestCluster.peer_node(p)).steals
    assert Enum.sum(steals) > 0
  end

  test "program definitions travel with the job" do
    program = """
    (def triple (lambda (n) (mul n 3)))
    (def main (lambda (xs) (pmap triple xs (lambda (v) (lt (length v) 4)))))
    """

    ctx = Cluster.load(program)
    assert Cluster.run(ctx, Enum.to_list(1..40)) == Enum.map(1..40, &(&1 * 3))
  end

  test "an error on a remote node surfaces as the same language error" do
    program = """
    (def main (lambda (xs)
      (dc xs (lambda (v) (lt (length v) 3)) halves
          (lambda (v) (if (eq (head v) 8) (head ()) v))
          append)))
    """

    ctx = Cluster.load(program)

    assert_raise Error, ~r/bad arguments to head/, fn ->
      Cluster.run(ctx, Enum.to_list(1..20))
    end
  end

  test "a peer dying mid job loses nothing: its pieces are solved again" do
    victim = TestCluster.start_peer(:node4, limit: 8)
    :ok = Cluster.wait_for_peers(3, 10_000)
    before = Enum.sum(for n <- [node() | Node.list()], do: Worker.stats(n).recovered)

    # Slow the base cases so the victim still has work when it dies.
    program = """
    (def spin (lambda (n) (if (eq n 0) 0 (spin (sub n 1)))))
    (def main (lambda (xs)
      (dc xs (lambda (v) (lt (length v) 4)) halves
          (lambda (v) (let z (spin 1000000) v))
          append)))
    """

    ctx = Cluster.load(program)

    Task.start(fn ->
      Process.sleep(1_500)
      TestCluster.stop_peer(victim)
    end)

    assert Cluster.run(ctx, Enum.to_list(1..256)) == Enum.to_list(1..256)

    # Recovery is counted on the node that solves the piece again.
    recovered =
      Enum.sum(for n <- [node() | Node.list()], do: Worker.stats(n).recovered) - before

    assert recovered > 0
  end
end
