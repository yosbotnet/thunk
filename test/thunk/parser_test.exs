defmodule Thunk.ParserTest do
  use ExUnit.Case, async: true

  alias Thunk.Parser

  defp one(source) do
    {:ok, [form]} = Parser.parse(source)
    form
  end

  describe "literals" do
    test "integers, negative integers and booleans" do
      assert one("42") == 42
      assert one("-7") == -7
      assert one("0") == 0
      assert one("true") == true
      assert one("false") == false
    end

    test "the empty list" do
      assert one("[]") == []
      assert one("[ ]") == []
    end

    test "strings and their escapes" do
      assert one(~S("hello world")) == "hello world"
      assert one(~S("")) == ""
      assert one(~S("a\"b")) == ~S(a"b)
      assert one(~S("a\\b")) == "a\\b"
      assert one(~S("a\nb")) == "a\nb"
      assert one(~S("a\tb")) == "a\tb"
      assert one("\"line one\nline two\"") == "line one\nline two"
      assert one(~S("città è ünïcode 日本")) == "città è ünïcode 日本"
    end
  end

  describe "names" do
    test "become atoms and may end with a question mark" do
      assert one("xs") == :xs
      assert one("merge_sorted") == :merge_sorted
      assert one("nil?") == :nil?
    end

    test "keywords are not names, but names may start with a keyword" do
      assert one("insert") == :insert
      assert one("iffy") == :iffy
      assert one("truthy") == :truthy
      assert {:error, _} = Parser.parse("in")
    end
  end

  describe "operators" do
    test "are calls of the primitives" do
      assert one("a + b") == [:add, :a, :b]
      assert one("a - b") == [:sub, :a, :b]
      assert one("a * b") == [:mul, :a, :b]
      assert one("a / b") == [:div, :a, :b]
      assert one("a % b") == [:mod, :a, :b]
      assert one("a < b") == [:lt, :a, :b]
      assert one("a == b") == [:eq, :a, :b]
      assert one("a :: b") == [:cons, :a, :b]
    end

    test "precedence" do
      assert one("x + n / x") == [:add, :x, [:div, :n, :x]]
      assert one("a * b + c < d") == [:lt, [:add, [:mul, :a, :b], :c], :d]
      assert one("x + 1 :: xs") == [:cons, [:add, :x, 1], :xs]
      assert one("(a + b) * c") == [:mul, [:add, :a, :b], :c]
    end

    test "arithmetic groups to the left, cons to the right" do
      assert one("a - b - c") == [:sub, [:sub, :a, :b], :c]
      assert one("a / b * c") == [:mul, [:div, :a, :b], :c]
      assert one("1 :: 2 :: []") == [:cons, 1, [:cons, 2, []]]
    end

    test "comparisons do not chain" do
      assert {:error, {1, 7, _}} = Parser.parse("a < b < c")
      assert {:error, _} = Parser.parse("a == b == c")
    end

    test "unary minus binds tighter than any binary operator" do
      assert one("-x") == [:sub, 0, :x]
      assert one("-x % 3") == [:mod, [:sub, 0, :x], 3]
      assert one("a - -3") == [:sub, :a, -3]
    end
  end

  describe "calls" do
    test "with any number of arguments" do
      assert one("f()") == [:f]
      assert one("f(x)") == [:f, :x]
      assert one("f(x, y + 1, g(z))") == [:f, :x, [:add, :y, 1], [:g, :z]]
    end

    test "of the result of a call or of a parenthesized expression" do
      assert one("f(1)(2)") == [[:f, 1], 2]
      assert one("(fn(x) -> x)(1)") == [[:lambda, [:x], :x], 1]
    end

    test "dc is an ordinary call" do
      assert one("dc(xs, small?, halves, base, merge)") ==
               [:dc, :xs, :small?, :halves, :base, :merge]
    end
  end

  describe "special forms" do
    test "fn" do
      assert one("fn(x, y) -> x + y") == [:lambda, [:x, :y], [:add, :x, :y]]
      assert one("fn() -> 1") == [:lambda, [], 1]
    end

    test "let" do
      assert one("let x = 2 in x * x") == [:let, :x, 2, [:mul, :x, :x]]
    end

    test "if" do
      assert one("if n < 2 then n else f(n)") == [:if, [:lt, :n, 2], :n, [:f, :n]]
    end

    test "bodies extend as far to the right as possible" do
      assert one("if c then a else b + 1") == [:if, :c, :a, [:add, :b, 1]]
      assert one("let x = 1 in x + 1") == [:let, :x, 1, [:add, :x, 1]]
      assert one("fn(x) -> x + 1") == [:lambda, [:x], [:add, :x, 1]]
      assert one("if a then b else if c then d else e") == [:if, :a, :b, [:if, :c, :d, :e]]
    end

    test "a comma ends a body" do
      assert one("f(fn(x) -> x, ys)") == [:f, [:lambda, [:x], :x], :ys]
    end
  end

  describe "programs" do
    test "definitions of values and of functions" do
      assert Parser.parse("def one = 1") == {:ok, [[:def, :one, 1]]}
      assert Parser.parse("def k() = 1") == {:ok, [[:def, :k, [:lambda, [], 1]]]}

      assert Parser.parse("def halves(xs) = split_at(length(xs) / 2, xs)") ==
               {:ok,
                [
                  [
                    :def,
                    :halves,
                    [:lambda, [:xs], [:split_at, [:div, [:length, :xs], 2], :xs]]
                  ]
                ]}
    end

    test "several definitions in a row" do
      assert Parser.parse("def a = 1\ndef b = a + 1") ==
               {:ok, [[:def, :a, 1], [:def, :b, [:add, :a, 1]]]}
    end

    test "empty input" do
      assert Parser.parse("") == {:ok, []}
      assert Parser.parse("  \n  ") == {:ok, []}
      assert Parser.parse("# only a comment") == {:ok, []}
    end
  end

  describe "comments and whitespace" do
    test "comments run to the end of the line" do
      assert one("f(a, # inside\n b) # after") == [:f, :a, :b]
    end

    test "tabs, carriage returns and newlines separate tokens" do
      assert one("f(a,\tb,\r\nc,\n d)") == [:f, :a, :b, :c, :d]
    end
  end

  describe "errors" do
    test "carry the line and column of the token" do
      assert Parser.parse("f(a))") == {:error, {1, 5, "syntax error before: ')'"}}

      assert Parser.parse("def f(x) =\n  x +\n  then") ==
               {:error, {3, 3, "syntax error before: then"}}
    end

    test "missing tokens at the end of the input" do
      assert Parser.parse("if a then b") == {:error, {1, 12, "unexpected end of input"}}
      assert Parser.parse("f(a") == {:error, {1, 4, "unexpected end of input"}}
    end

    test "two expressions in a row are an error" do
      assert {:error, {1, 3, _}} = Parser.parse("1 2")
    end

    test "characters that are not part of the language" do
      assert Parser.parse("x @ y") == {:error, {1, 3, ~S(illegal characters "@")}}
    end

    test "bad strings" do
      assert {:error, {1, _, "invalid escape"}} = Parser.parse(~S("ab\q"))
      assert {:error, {1, _, "unterminated string"}} = Parser.parse(~S("abc))
    end
  end

  describe "parse!/1" do
    test "returns the forms directly" do
      assert Parser.parse!("f(1)") == [[:f, 1]]
    end

    test "raises ArgumentError with message and position" do
      assert_raise ArgumentError, "line 1, column 1: syntax error before: ')'", fn ->
        Parser.parse!(")")
      end
    end
  end
end
