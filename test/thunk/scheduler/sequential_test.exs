defmodule Thunk.Scheduler.SequentialTest do
  use ExUnit.Case, async: true

  alias Thunk.{Context, Error, Eval, Parser}

  @ctx %Context{scheduler: Thunk.Scheduler.Sequential}

  defp ev(source, env \\ %{}) do
    [form] = Parser.parse!(source)
    Eval.eval(form, env, @ctx)
  end

  # Splits an integer n into two integers that add up to n. Lets dc be
  # tested without any list library.
  @split "fn(n) -> n / 2 :: n - n / 2 :: []"
  @small "fn(n) -> n < 2"

  test "a base case is solved directly" do
    assert ev("dc(5, fn(n) -> true, #{@split}, fn(n) -> n * 10, add)") == 50
  end

  test "splits, recurses and merges" do
    assert ev("dc(10, #{@small}, #{@split}, fn(n) -> n, add)") == 10
    assert ev("dc(1000, #{@small}, #{@split}, fn(n) -> 1, add)") == 1000
  end

  test "merge receives left and right in split order" do
    pair = "fn(l, r) -> l :: r :: []"
    assert ev("dc(3, #{@small}, #{@split}, fn(n) -> n, #{pair})") == [1, [1, 1]]
  end

  test "the input can be any value" do
    assert ev("dc([], fn(v) -> true, #{@split}, fn(v) -> v, add)") == []
  end

  test "dc inside a base case works" do
    inner = "fn(n) -> dc(n, #{@small}, #{@split}, fn(m) -> m, add)"
    assert ev("dc(20, fn(n) -> n < 6, #{@split}, #{inner}, add)") == 20
  end

  test "dc uses definitions" do
    ctx = %{@ctx | defs: %{small?: ev(@small), halve: ev(@split)}}
    [form] = Parser.parse!("dc(8, small?, halve, fn(n) -> n, add)")
    assert Eval.eval(form, %{}, ctx) == 8
  end

  test "a predicate that is not a boolean is an error" do
    assert_raise Error, ~r/dc predicate/, fn ->
      ev("dc(4, fn(n) -> 1, #{@split}, fn(n) -> n, add)")
    end
  end

  test "a split that is not a list of two values is an error" do
    assert_raise Error, ~r/dc split/, fn ->
      ev("dc(4, #{@small}, fn(n) -> n :: [], fn(n) -> n, add)")
    end

    assert_raise Error, ~r/dc split/, fn ->
      ev("dc(4, #{@small}, fn(n) -> n, fn(n) -> n, add)")
    end
  end

  test "malformed dc is an error" do
    assert_raise Error, ~r/malformed dc/, fn -> ev("dc(1, 2)") end
  end
end
