defmodule Thunk.EvalTest do
  use ExUnit.Case, async: true

  alias Thunk.{Context, Error, Eval, Parser}

  defp ev(source, env \\ %{}, ctx \\ %Context{}) do
    [form] = Parser.parse!(source)
    Eval.eval(form, env, ctx)
  end

  # Forms the grammar cannot produce, to check that the evaluator still
  # rejects them.
  defp ev_form(form), do: Eval.eval(form, %{}, %Context{})

  # Builds a definitions table from def forms. Only for these tests,
  # the real loader arrives with Thunk.load.
  defp defs(source) do
    Enum.reduce(Parser.parse!(source), %Context{}, fn [:def, name, expr], ctx ->
      %{ctx | defs: Map.put(ctx.defs, name, Eval.eval(expr, %{}, ctx))}
    end)
  end

  describe "self-evaluating forms" do
    test "literals evaluate to themselves" do
      assert ev("42") == 42
      assert ev("-3") == -3
      assert ev("true") == true
      assert ev("false") == false
      assert ev(~S("hi")) == "hi"
      assert ev("[]") == []
    end
  end

  describe "symbols" do
    test "are looked up in the environment" do
      assert ev("x", %{x: 7}) == 7
    end

    test "then in the definitions table" do
      ctx = %Context{defs: %{x: 8}}
      assert ev("x", %{}, ctx) == 8
      assert ev("x", %{x: 7}, ctx) == 7
    end

    test "then among the primitives, as values" do
      assert ev("add") == {:primitive, :add}
      assert ev("add", %{}, %Context{defs: %{add: 1}}) == 1
    end

    test "unbound symbols are errors" do
      assert_raise Error, ~r/unbound symbol nope/, fn -> ev("nope") end
    end
  end

  describe "lambda and application" do
    test "lambda captures the environment" do
      assert ev("fn(x) -> x", %{y: 1}) == {:closure, [:x], :x, %{y: 1}}
    end

    test "applying a closure binds parameters" do
      assert ev("(fn(x, y) -> x - y)(10, 3)") == 7
    end

    test "applying a primitive" do
      assert ev("add(1, 2)") == 3
      assert ev("1 :: 2 :: []") == [1, 2]
      assert ev("cons(1, cons(2, []))") == [1, 2]
    end

    test "closures nest and are lexically scoped" do
      assert ev("(fn(x) -> fn(y) -> x + y)(1)(2)") == 3
      assert ev("(fn(f) -> f(5))(fn(x) -> x * x)") == 25
    end

    test "a closure sees its captured environment, not the caller's" do
      ctx = defs("def k(x) = fn() -> x")
      assert ev("let x = 1 in let g = k(2) in let x = 3 in g()", %{}, ctx) == 2
    end

    test "calls with many arguments" do
      assert ev("(fn() -> 7)()") == 7
      assert ev("(fn(a, b, c, d) -> (a + b) - (c + d))(10, 20, 3, 4)") == 23
      assert ev("(fn(a, b, c, d, e) -> a :: e :: [])(1, 2, 3, 4, 5)") == [1, 5]
    end

    test "arguments are evaluated left to right, the first error wins" do
      assert_raise Error, ~r/bad arguments to head/, fn -> ev("head([]) + 1 / 0") end
      assert_raise Error, ~r/bad arguments to div/, fn -> ev("1 / 0 + head([])") end

      assert_raise Error, ~r/bad arguments to tail/, fn ->
        ev("(fn(a, b, c, d) -> a)(1, 2, tail([]), head([]))")
      end
    end

    test "the callable is evaluated before the arguments" do
      assert_raise Error, ~r/unbound symbol nope/, fn -> ev("nope(head([]))") end
    end

    test "all arguments are evaluated before an arity error" do
      assert_raise Error, ~r/bad arguments to head/, fn -> ev("(fn(x) -> x)(1, head([]))") end
    end

    test "a repeated parameter name takes the last argument" do
      assert ev("(fn(x, x) -> x)(1, 2)") == 2
    end

    test "parameters shadow captured variables without changing them" do
      assert ev("let x = 1 in let f = fn(x) -> x in f(2) :: x :: []") == [2, 1]
    end

    test "closures that differ only in an unused capture are not equal" do
      assert ev("(let unused = 1 in fn(x) -> x) == (let unused = 2 in fn(x) -> x)") == false
    end

    test "arity mismatch is an error" do
      assert_raise Error, ~r/expected 1 argument/, fn -> ev("(fn(x) -> x)(1, 2)") end
      assert_raise Error, ~r/expected 2 argument/, fn -> ev("(fn(x, y) -> x)()") end
    end

    test "calling a value that is not a function is an error" do
      assert_raise Error, ~r/not a function/, fn -> ev("1(2)") end
      assert_raise Error, ~r/not a function/, fn -> ev("\"s\"(2)") end
    end

    test "malformed lambda is an error" do
      assert_raise Error, ~r/malformed lambda/, fn -> ev_form([:lambda, :x, :x]) end
      assert_raise Error, ~r/malformed lambda/, fn -> ev_form([:lambda, [:x]]) end
    end
  end

  describe "if" do
    test "chooses a branch on a boolean" do
      assert ev("if true then 1 else 2") == 1
      assert ev("if false then 1 else 2") == 2
      assert ev("if 1 < 2 then 1 else 2") == 1
    end

    test "only the chosen branch is evaluated" do
      assert ev("if true then 1 else head([])") == 1
      assert ev("if false then head([]) else 2") == 2
    end

    test "a non-boolean condition is an error" do
      assert_raise Error, ~r/if condition/, fn -> ev("if 1 then 2 else 3") end
      assert_raise Error, ~r/if condition/, fn -> ev("if [] then 2 else 3") end
    end

    test "malformed if is an error" do
      assert_raise Error, ~r/malformed if/, fn -> ev_form([:if, true, 1]) end
    end
  end

  describe "let" do
    test "binds one name in the body" do
      assert ev("let x = 2 in x * x") == 4
    end

    test "nests and shadows" do
      assert ev("let x = 1 in let y = 2 in x + y") == 3
      assert ev("let x = 1 in let x = 2 in x") == 2
      assert ev("let x = 1 in let y = x + 1 in let x = 10 in x + y") == 12
    end

    test "malformed let is an error" do
      assert_raise Error, ~r/malformed let/, fn -> ev_form([:let, 1, 2, 3]) end
      assert_raise Error, ~r/malformed let/, fn -> ev_form([:let, :x, 2]) end
    end
  end

  describe "def" do
    test "is not allowed inside expressions" do
      assert_raise Error, ~r/top level/, fn -> ev_form([:let, :x, [:def, :y, 1], :x]) end
    end
  end

  describe "recursion through the definitions table" do
    test "factorial" do
      ctx = defs("def fact(n) = if n < 2 then 1 else n * fact(n - 1)")
      assert ev("fact(10)", %{}, ctx) == 3_628_800
    end

    test "mutual recursion works regardless of definition order" do
      ctx =
        defs("""
        def even?(n) = if n == 0 then true else odd?(n - 1)
        def odd?(n) = if n == 0 then false else even?(n - 1)
        """)

      assert ev("even?(10)", %{}, ctx) == true
      assert ev("odd?(7)", %{}, ctx) == true
    end

    test "tail calls run in constant stack" do
      ctx = defs("def loop(n) = if n == 0 then 0 else loop(n - 1)")
      parent = self()

      # A million iterations. Without proper tail calls the interpreter
      # would need a million Elixir frames, far more than this heap limit.
      {pid, ref} =
        :erlang.spawn_opt(
          fn -> send(parent, {:done, ev("loop(1000000)", %{}, ctx)}) end,
          [:monitor, max_heap_size: %{size: 1_000_000, kill: true, error_logger: false}]
        )

      assert_receive {:done, 0}, 30_000
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
    end
  end
end
