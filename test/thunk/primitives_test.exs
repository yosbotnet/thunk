defmodule Thunk.PrimitivesTest do
  use ExUnit.Case, async: true

  alias Thunk.{Error, Primitives}

  test "there are exactly thirteen primitives" do
    assert Enum.sort(Primitives.names()) ==
             Enum.sort([
               :add,
               :sub,
               :mul,
               :div,
               :mod,
               :lt,
               :eq,
               :cons,
               :head,
               :tail,
               :nil?,
               :chars,
               :string
             ])
  end

  test "lookup returns a primitive value for known names only" do
    assert Primitives.lookup(:add) == {:ok, {:primitive, :add}}
    assert Primitives.lookup(:length) == :error
  end

  test "integer arithmetic" do
    assert Primitives.call(:add, [2, 3]) == 5
    assert Primitives.call(:sub, [2, 3]) == -1
    assert Primitives.call(:mul, [4, 5]) == 20
    assert Primitives.call(:div, [7, 2]) == 3
    assert Primitives.call(:div, [-7, 2]) == -3
    assert Primitives.call(:mod, [7, 3]) == 1
    assert Primitives.call(:mod, [-7, 3]) == 2
  end

  test "division by zero is an error" do
    assert_raise Error, fn -> Primitives.call(:div, [1, 0]) end
    assert_raise Error, fn -> Primitives.call(:mod, [1, 0]) end
  end

  test "comparison" do
    assert Primitives.call(:lt, [1, 2]) == true
    assert Primitives.call(:lt, [2, 2]) == false
    assert Primitives.call(:eq, [[1, 2], [1, 2]]) == true
    assert Primitives.call(:eq, ["a", "b"]) == false
    assert Primitives.call(:eq, [1, true]) == false
  end

  test "lists" do
    assert Primitives.call(:cons, [1, []]) == [1]
    assert Primitives.call(:cons, [1, [2]]) == [1, 2]
    assert Primitives.call(:head, [[1, 2]]) == 1
    assert Primitives.call(:tail, [[1, 2]]) == [2]
    assert Primitives.call(:nil?, [[]]) == true
    assert Primitives.call(:nil?, [[1]]) == false
    assert Primitives.call(:nil?, [0]) == false
  end

  test "head and tail of the empty list are errors" do
    assert_raise Error, fn -> Primitives.call(:head, [[]]) end
    assert_raise Error, fn -> Primitives.call(:tail, [[]]) end
  end

  test "strings convert to and from codepoint lists" do
    assert Primitives.call(:chars, ["ab"]) == [?a, ?b]
    assert Primitives.call(:chars, ["è"]) == [232]
    assert Primitives.call(:string, [[?a, ?b]]) == "ab"
    assert Primitives.call(:string, [[]]) == ""
    assert Primitives.call(:string, [Primitives.call(:chars, ["città 日本"])]) == "città 日本"
  end

  test "wrong argument types and arities are errors" do
    assert_raise Error, fn -> Primitives.call(:add, [1, "2"]) end
    assert_raise Error, fn -> Primitives.call(:add, [1]) end
    assert_raise Error, fn -> Primitives.call(:cons, [1, 2]) end
    assert_raise Error, fn -> Primitives.call(:chars, [1]) end
    assert_raise Error, fn -> Primitives.call(:string, [[-1]]) end
    assert_raise Error, fn -> Primitives.call(:nope, [1]) end
  end
end
