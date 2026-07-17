defmodule Thunk.ParserTest do
  use ExUnit.Case, async: true

  alias Thunk.Parser

  describe "integers" do
    test "parses positive and negative integers" do
      assert Parser.parse("42") == {:ok, [42]}
      assert Parser.parse("-7") == {:ok, [-7]}
      assert Parser.parse("0") == {:ok, [0]}
    end

    test "a lone minus is a symbol" do
      assert Parser.parse("-") == {:ok, [:-]}
      assert Parser.parse("(- 5 3)") == {:ok, [[:-, 5, 3]]}
    end

    test "a minus followed by letters is a symbol" do
      assert Parser.parse("-x") == {:ok, [:"-x"]}
    end

    test "a leading plus does not make a number" do
      assert Parser.parse("+5") == {:ok, [:"+5"]}
    end
  end

  describe "booleans" do
    test "true and false become Elixir booleans" do
      assert Parser.parse("true false") == {:ok, [true, false]}
    end

    test "symbols that only start with true or false stay symbols" do
      assert Parser.parse("truthy false?") == {:ok, [:truthy, :false?]}
    end
  end

  describe "strings" do
    test "plain string" do
      assert Parser.parse(~S("hello world")) == {:ok, ["hello world"]}
    end

    test "empty string" do
      assert Parser.parse(~S("")) == {:ok, [""]}
    end

    test "supported escapes" do
      assert Parser.parse(~S("a\"b")) == {:ok, [~S(a"b)]}
      assert Parser.parse(~S("a\\b")) == {:ok, ["a\\b"]}
      assert Parser.parse(~S("a\nb")) == {:ok, ["a\nb"]}
      assert Parser.parse(~S("a\tb")) == {:ok, ["a\tb"]}
    end

    test "literal newline inside a string" do
      assert Parser.parse("\"line one\nline two\"") == {:ok, ["line one\nline two"]}
    end

    test "invalid escape is an error at the backslash" do
      assert Parser.parse(~S("ab\q")) == {:error, {1, 4, "invalid escape"}}
    end

    test "unterminated string reports the end of input" do
      assert Parser.parse(~S("abc)) == {:error, {1, 5, "unterminated string"}}
    end

    test "unterminated string spanning lines" do
      assert Parser.parse("(x \"ab\ncd") == {:error, {2, 3, "unterminated string"}}
    end

    test "unicode in strings" do
      assert Parser.parse(~S("città è ünïcode 日本")) == {:ok, ["città è ünïcode 日本"]}
    end
  end

  describe "symbols" do
    test "symbols with punctuation" do
      assert Parser.parse("merge-sorted nil? + < <= set! a.b") ==
               {:ok, [:"merge-sorted", :nil?, :+, :<, :<=, :set!, :"a.b"]}
    end

    test "unicode in symbols" do
      assert Parser.parse("città λ") == {:ok, [:città, :λ]}
    end

    test "symbols end at a parenthesis or a quote" do
      assert Parser.parse("(foo)") == {:ok, [[:foo]]}
      assert Parser.parse(~S(foo"bar")) == {:ok, [:foo, "bar"]}
    end
  end

  describe "lists" do
    test "empty list" do
      assert Parser.parse("()") == {:ok, [[]]}
      assert Parser.parse("( )") == {:ok, [[]]}
    end

    test "nested lists" do
      assert Parser.parse("(def halves (lambda (xs) (split-at xs (div (length xs) 2))))") ==
               {:ok,
                [
                  [
                    :def,
                    :halves,
                    [:lambda, [:xs], [:"split-at", :xs, [:div, [:length, :xs], 2]]]
                  ]
                ]}
    end

    test "deeply nested empty lists" do
      assert Parser.parse("((()))") == {:ok, [[[[]]]]}
    end
  end

  describe "comments and whitespace" do
    test "comments run to the end of the line" do
      assert Parser.parse("; only a comment") == {:ok, []}
      assert Parser.parse("(a ; inside\n b) ; after") == {:ok, [[:a, :b]]}
    end

    test "a semicolon ends a symbol" do
      assert Parser.parse("foo;bar\nbaz") == {:ok, [:foo, :baz]}
    end

    test "tabs, carriage returns and newlines separate tokens" do
      assert Parser.parse("a\tb\r\nc\n d") == {:ok, [:a, :b, :c, :d]}
    end

    test "empty input" do
      assert Parser.parse("") == {:ok, []}
      assert Parser.parse("  \n  ") == {:ok, []}
    end
  end

  describe "multiple top-level forms" do
    test "mixed forms with a comment" do
      assert Parser.parse("(if (lt n 2) n (add 1 -3)) ; comment\n\"a\\nb\" true ()") ==
               {:ok, [[:if, [:lt, :n, 2], :n, [:add, 1, -3]], "a\nb", true, []]}
    end
  end

  describe "errors" do
    test "unexpected closing parenthesis" do
      assert Parser.parse(")") == {:error, {1, 1, "unexpected )"}}
      assert Parser.parse("(a b))") == {:error, {1, 6, "unexpected )"}}
    end

    test "unexpected closing parenthesis on a later line" do
      assert Parser.parse("(a)\n  )") == {:error, {2, 3, "unexpected )"}}
    end

    # For unterminated constructs the reported position is the one just past
    # the last character of the input, i.e. where the missing ")" would go.
    test "missing closing parenthesis reports the end of input" do
      assert Parser.parse("(a b") == {:error, {1, 5, "unexpected end of input"}}
      assert Parser.parse("(a\n(b") == {:error, {2, 3, "unexpected end of input"}}
    end

    test "the first error wins" do
      assert Parser.parse("(a))\n(b") == {:error, {1, 4, "unexpected )"}}
    end
  end

  describe "parse!/1" do
    test "returns the forms directly" do
      assert Parser.parse!("(a 1)") == [[:a, 1]]
    end

    test "raises ArgumentError with message and position" do
      assert_raise ArgumentError, "line 1, column 1: unexpected )", fn ->
        Parser.parse!(")")
      end

      assert_raise ArgumentError, "line 1, column 5: unterminated string", fn ->
        Parser.parse!(~S("abc))
      end
    end
  end
end
