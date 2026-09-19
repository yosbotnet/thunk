defmodule Thunk.EvalTest do
  use ExUnit.Case, async: true

  alias Thunk.{Context, Error, Eval, Parser}

  defp ev(source, env \\ %{}, ctx \\ %Context{}) do
    [form] = Parser.parse!(source)
    Eval.eval(form, env, ctx)
  end

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
      assert ev("()") == []
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
      assert ev("(lambda (x) x)", %{y: 1}) == {:closure, [:x], :x, %{y: 1}}
    end

    test "applying a closure binds parameters" do
      assert ev("((lambda (x y) (sub x y)) 10 3)") == 7
    end

    test "applying a primitive" do
      assert ev("(add 1 2)") == 3
      assert ev("(cons 1 (cons 2 ()))") == [1, 2]
    end

    test "closures nest and are lexically scoped" do
      assert ev("(((lambda (x) (lambda (y) (add x y))) 1) 2)") == 3
      assert ev("((lambda (f) (f 5)) (lambda (x) (mul x x)))") == 25
    end

    test "a closure sees its captured environment, not the caller's" do
      ctx = defs("(def k (lambda (x) (lambda () x)))")
      assert ev("(let x 1 (let g (k 2) (let x 3 (g))))", %{}, ctx) == 2
    end

    test "calls with many arguments" do
      assert ev("((lambda () 7))") == 7
      assert ev("((lambda (a b c d) (sub (add a b) (add c d))) 10 20 3 4)") == 23
      assert ev("((lambda (a b c d e) (cons a (cons e ()))) 1 2 3 4 5)") == [1, 5]
    end

    test "arguments are evaluated left to right, the first error wins" do
      assert_raise Error, ~r/bad arguments to head/, fn -> ev("(add (head ()) (div 1 0))") end
      assert_raise Error, ~r/bad arguments to div/, fn -> ev("(add (div 1 0) (head ()))") end

      assert_raise Error, ~r/bad arguments to tail/, fn ->
        ev("((lambda (a b c d) a) 1 2 (tail ()) (head ()))")
      end
    end

    test "the callable is evaluated before the arguments" do
      assert_raise Error, ~r/unbound symbol nope/, fn -> ev("(nope (head ()))") end
    end

    test "all arguments are evaluated before an arity error" do
      assert_raise Error, ~r/bad arguments to head/, fn -> ev("((lambda (x) x) 1 (head ()))") end
    end

    test "arity mismatch is an error" do
      assert_raise Error, ~r/expected 1 argument/, fn -> ev("((lambda (x) x) 1 2)") end
      assert_raise Error, ~r/expected 2 argument/, fn -> ev("((lambda (x y) x))") end
    end

    test "calling a value that is not a function is an error" do
      assert_raise Error, ~r/not a function/, fn -> ev("(1 2)") end
      assert_raise Error, ~r/not a function/, fn -> ev("(\"s\" 2)") end
    end

    test "malformed lambda is an error" do
      assert_raise Error, ~r/malformed lambda/, fn -> ev("(lambda x x)") end
      assert_raise Error, ~r/malformed lambda/, fn -> ev("(lambda (x))") end
    end
  end

  describe "if" do
    test "chooses a branch on a boolean" do
      assert ev("(if true 1 2)") == 1
      assert ev("(if false 1 2)") == 2
      assert ev("(if (lt 1 2) 1 2)") == 1
    end

    test "only the chosen branch is evaluated" do
      assert ev("(if true 1 (head ()))") == 1
      assert ev("(if false (head ()) 2)") == 2
    end

    test "a non-boolean condition is an error" do
      assert_raise Error, ~r/if condition/, fn -> ev("(if 1 2 3)") end
      assert_raise Error, ~r/if condition/, fn -> ev("(if () 2 3)") end
    end

    test "malformed if is an error" do
      assert_raise Error, ~r/malformed if/, fn -> ev("(if true 1)") end
    end
  end

  describe "let" do
    test "binds one name in the body" do
      assert ev("(let x 2 (mul x x))") == 4
    end

    test "nests and shadows" do
      assert ev("(let x 1 (let y 2 (add x y)))") == 3
      assert ev("(let x 1 (let x 2 x))") == 2
      assert ev("(let x 1 (let y (add x 1) (let x 10 (add x y))))") == 12
    end

    test "malformed let is an error" do
      assert_raise Error, ~r/malformed let/, fn -> ev("(let 1 2 3)") end
      assert_raise Error, ~r/malformed let/, fn -> ev("(let x 2)") end
    end
  end

  describe "def" do
    test "is not allowed inside expressions" do
      assert_raise Error, ~r/top level/, fn -> ev("(let x (def y 1) x)") end
    end
  end

  describe "recursion through the definitions table" do
    test "factorial" do
      ctx = defs("(def fact (lambda (n) (if (lt n 2) 1 (mul n (fact (sub n 1))))))")
      assert ev("(fact 10)", %{}, ctx) == 3_628_800
    end

    test "mutual recursion works regardless of definition order" do
      ctx =
        defs("""
        (def even? (lambda (n) (if (eq n 0) true (odd? (sub n 1)))))
        (def odd? (lambda (n) (if (eq n 0) false (even? (sub n 1)))))
        """)

      assert ev("(even? 10)", %{}, ctx) == true
      assert ev("(odd? 7)", %{}, ctx) == true
    end

    test "tail calls run in constant stack" do
      ctx = defs("(def loop (lambda (n) (if (eq n 0) 0 (loop (sub n 1)))))")
      parent = self()

      # A million iterations. Without proper tail calls the interpreter
      # would need a million Elixir frames, far more than this heap limit.
      {pid, ref} =
        :erlang.spawn_opt(
          fn -> send(parent, {:done, ev("(loop 1000000)", %{}, ctx)}) end,
          [:monitor, max_heap_size: %{size: 1_000_000, kill: true, error_logger: false}]
        )

      assert_receive {:done, 0}, 30_000
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
    end
  end
end
