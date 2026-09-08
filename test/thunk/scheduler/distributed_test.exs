defmodule Thunk.Scheduler.DistributedTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Thunk.{Context, Error, Piece, Worker}
  alias Thunk.Scheduler.{Distributed, Sequential}

  @split "(lambda (n) (cons (div n 2) (cons (sub n (div n 2)) ())))"
  @small "(lambda (n) (lt n 2))"

  setup do
    on_exit(fn -> Worker.set_limit(0) end)
    :ok
  end

  defp ctx(limit) do
    Worker.set_limit(limit)
    Thunk.with_scheduler(Worker.prelude(), Distributed)
  end

  defp steal_until_piece(owner) do
    GenServer.cast(Worker, {:steal, self()})

    receive do
      {:piece, _piece} -> send(owner, :thief_has_it)
      :none -> steal_until_piece(owner)
    end
  end

  test "with no local capacity and no peers every piece is taken back" do
    ctx = ctx(0)
    assert Thunk.eval("(dc 100 #{@small} #{@split} (lambda (n) n) add)", ctx) == 100
  end

  test "with local capacity pieces are evaluated by other processes" do
    ctx = ctx(4)
    %{evaluated: before} = Worker.stats()
    assert Thunk.eval("(dc 100 #{@small} #{@split} (lambda (n) n) add)", ctx) == 100
    # evaluators finish asynchronously from the worker's point of view
    Process.sleep(50)
    assert Worker.stats().evaluated > before
  end

  test "agrees with the sequential scheduler on the demos" do
    for limit <- [0, 3] do
      ctx = ctx(limit)
      seq = Thunk.with_scheduler(ctx, Sequential)

      xs = Enum.shuffle(1..300)
      program = "(mergesort xs (lambda (v) (lt (length v) 8)))"
      assert Thunk.eval(program, ctx, %{xs: xs}) == Thunk.eval(program, seq, %{xs: xs})

      text = Enum.map_join(1..200, " ", fn _ -> Enum.random(~w(a b c d e)) end)
      program = "(word-count t (lambda (v) (lt (length v) 10)))"
      assert Thunk.eval(program, ctx, %{t: text}) == Thunk.eval(program, seq, %{t: text})
    end
  end

  test "a language error inside a locally stolen piece is re-raised in the owner" do
    ctx = ctx(4)
    crash = "(dc 8 #{@small} #{@split} (lambda (n) (if (eq n 1) (head ()) n)) add)"
    assert_raise Error, ~r/bad arguments to head/, fn -> Thunk.eval(crash, ctx) end
  end

  test "a piece stolen by a process that dies makes the owner fail" do
    ctx = ctx(0)
    owner = self()

    # A fake thief: keeps asking until it gets a piece, then dies without
    # ever claiming it. The job is big enough that its right half sits in
    # the deque while the left half is being solved.
    thief = spawn(fn -> steal_until_piece(owner) end)

    program = "(dc 200000 #{@small} #{@split} (lambda (n) n) add)"

    task =
      Task.async(fn ->
        assert_raise Error, ~r/lost/, fn -> Thunk.eval(program, ctx) end
      end)

    assert_receive :thief_has_it, 1_000
    Task.await(task, 5_000)
    refute Process.alive?(thief)
  end

  test "run_piece sends the result to the owner and uses the job's definitions" do
    id = make_ref()
    defs = Thunk.load("(def double (lambda (n) (mul n 2)))", Worker.prelude()).defs
    Worker.register_job(id, defs)

    # build the piece by hand: base case that calls the job's definition
    truthy = Thunk.eval("(lambda (v) true)")
    work = %Thunk.Work{value: 21, pred: truthy, split: truthy, base: defs.double, merge: truthy}
    piece = %Piece{work: work, ref: make_ref(), reply_to: self(), job: {id, node()}}

    Distributed.run_piece(piece)
    assert_receive {:result, ref, 42}
    assert ref == piece.ref
    assert %Context{} = Thunk.with_scheduler(Worker.prelude(), Distributed)
  end
end
