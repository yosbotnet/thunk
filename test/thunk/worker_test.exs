defmodule Thunk.WorkerTest do
  use ExUnit.Case, async: false

  alias Thunk.{Context, Piece, Work, Worker}

  # A piece whose work is a trivial base case. Never evaluated in these
  # tests: the limit is 0, so nothing is started locally.
  defp piece(ref \\ make_ref()) do
    closure = Thunk.eval("(lambda (v) v)")
    truthy = Thunk.eval("(lambda (v) true)")
    work = %Work{value: 1, pred: truthy, split: closure, base: closure, merge: closure}
    %Piece{work: work, ref: ref, reply_to: self(), job: nil}
  end

  setup do
    Worker.set_limit(0)
    on_exit(fn -> Worker.set_limit(0) end)
    :ok
  end

  test "the prelude context is available" do
    assert %Context{defs: %{fold: _}} = Worker.prelude()
  end

  test "a pushed piece can be taken back" do
    p = piece()
    Worker.push(p)
    assert Worker.take_back(p.ref) == {:ok, p}
  end

  test "taking back an unknown ref is an error" do
    assert Worker.take_back(make_ref()) == {:error, :unknown}
  end

  test "a thief gets the oldest piece and the owner learns who took it" do
    first = piece()
    second = piece()
    Worker.push(first)
    Worker.push(second)

    GenServer.cast(Worker, {:steal, self()})
    assert_receive {:piece, ^first}, 1_000

    assert Worker.take_back(first.ref) == {:stolen, self()}
    assert Worker.take_back(second.ref) == {:ok, second}
  end

  test "stealing from an empty deque answers none" do
    GenServer.cast(Worker, {:steal, self()})
    assert_receive :none, 1_000
  end

  test "jobs are registered and fetched by id" do
    id = make_ref()
    assert Worker.job_context({id, node()}) == :unknown
    assert Worker.register_job(id, %{x: 1}) == :ok
    assert {:ok, %Context{defs: %{x: 1}, job: {^id, _}}} = Worker.job_context({id, node()})
    assert Worker.fetch_job(node(), id) == {:ok, %{x: 1}}
    assert Worker.fetch_job(node(), make_ref()) == :error
  end

  test "a piece with no job gets the prelude context" do
    assert {:ok, %Context{defs: %{fold: _}, job: nil}} = Worker.job_context(nil)
  end

  test "stats count steals" do
    %{stolen_from: before} = Worker.stats()
    p = piece()
    Worker.push(p)
    GenServer.cast(Worker, {:steal, self()})
    assert_receive {:piece, ^p}, 1_000
    assert %{stolen_from: after_steal} = Worker.stats()
    assert after_steal == before + 1
  end
end
