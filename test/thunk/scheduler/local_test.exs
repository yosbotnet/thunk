defmodule Thunk.Scheduler.LocalTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Thunk.Context
  alias Thunk.Scheduler.{Local, Sequential}

  @split "(lambda (n) (cons (div n 2) (cons (sub n (div n 2)) ())))"
  @small "(lambda (n) (lt n 2))"

  defp both(source) do
    {Thunk.eval(source, Thunk.with_scheduler(%Context{}, Sequential)),
     Thunk.eval(source, Thunk.with_scheduler(%Context{}, Local))}
  end

  test "gives the same results as the sequential scheduler" do
    pair = "(lambda (l r) (cons l (cons r ())))"

    for source <- [
          "(dc 10 #{@small} #{@split} (lambda (n) n) add)",
          "(dc 1000 #{@small} #{@split} (lambda (n) 1) add)",
          "(dc 7 #{@small} #{@split} (lambda (n) n) #{pair})",
          "(dc 5 (lambda (n) true) #{@split} (lambda (n) (mul n 10)) add)"
        ] do
      {expected, actual} = both(source)
      assert actual == expected
    end
  end

  test "works with definitions loaded through Thunk.load" do
    ctx =
      Thunk.load(
        "(def main (lambda (n) (dc n #{@small} #{@split} (lambda (m) m) add)))",
        Thunk.with_scheduler(%Context{}, Local)
      )

    assert Thunk.run(ctx, 64) == 64
  end

  test "a crash in any half brings down the job" do
    ctx = Thunk.with_scheduler(%Context{}, Local)
    crash_right = "(dc 2 #{@small} #{@split} (lambda (n) (if (eq n 1) (head ()) n)) add)"

    {pid, ref} = spawn_monitor(fn -> Thunk.eval(crash_right, ctx) end)
    assert_receive {:DOWN, ^ref, :process, ^pid, reason}, 5_000
    refute reason == :normal
  end
end
