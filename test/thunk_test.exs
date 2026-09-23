defmodule ThunkTest do
  use ExUnit.Case, async: true

  alias Thunk.{Context, Error}

  test "load evaluates defs in order into the context" do
    ctx = Thunk.load("def one = 1 def two = one + 1")
    assert ctx.defs == %{one: 1, two: 2}
  end

  test "load builds on an existing context" do
    ctx = Thunk.load("def one = 1")
    ctx = Thunk.load("def two = one + 1", ctx)
    assert ctx.defs.two == 2
  end

  test "a later def replaces an earlier one" do
    ctx = Thunk.load("def x = 1 def x = 2")
    assert ctx.defs.x == 2
  end

  test "only defs are allowed at top level" do
    assert_raise Error, ~r/expected a def/, fn -> Thunk.load("add(1, 2)") end
    assert_raise ArgumentError, ~r/syntax error/, fn -> Thunk.load("def 1 = 2") end
  end

  test "run applies main to the input" do
    ctx = Thunk.load("def main(x) = x * 2")
    assert Thunk.run(ctx, 21) == 42
  end

  test "run without main is an error" do
    assert_raise Error, ~r/no main/, fn -> Thunk.run(%Context{}, 1) end
  end

  test "eval evaluates one expression with an environment" do
    assert Thunk.eval("x + 1", %Context{}, %{x: 1}) == 2
    assert Thunk.eval("1 :: []") == [1]
  end

  test "eval rejects anything but one expression" do
    assert_raise Error, ~r/exactly one/, fn -> Thunk.eval("") end
    assert_raise ArgumentError, ~r/syntax error/, fn -> Thunk.eval("1 2") end
  end

  test "with_scheduler swaps the scheduler" do
    ctx = Thunk.with_scheduler(%Context{}, SomeScheduler)
    assert ctx.scheduler == SomeScheduler
  end
end
