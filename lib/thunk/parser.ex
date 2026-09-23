defmodule Thunk.Parser do
  @moduledoc """
  Reader for Thunk source code.

  The tokens are defined in `src/thunk_lexer.xrl` (leex) and the grammar
  in `src/thunk_parser.yrl` (yecc). The result is plain Elixir data that
  the evaluator works on directly: integers, booleans and strings map to
  themselves, names to atoms, and every call, operator and special form
  to a list whose head says what it is.

      def isqrt(n) = if n < 2 then n else isqrt_iter(n, n)

  becomes

      [:def, :isqrt, [:lambda, [:n], [:if, [:lt, :n, 2], :n, [:isqrt_iter, :n, :n]]]]

  A source is either a sequence of definitions or a single expression.

      program    = definition*  |  expr
      definition = "def" name "=" expr
                 | "def" name "(" [name ("," name)*] ")" "=" expr
      expr       = "if" expr "then" expr "else" expr
                 | "let" name "=" expr "in" expr
                 | "fn" "(" [name ("," name)*] ")" "->" expr
                 | expr op expr  |  "-" expr  |  call
      call       = atom ("(" [expr ("," expr)*] ")")*
      atom       = name | integer | string | "true" | "false" | "[]" | "(" expr ")"

  Operators, from the loosest to the tightest: `< ==` (not chained),
  `::` (right), `+ -`, `* / %` (left). Each one is the call of a
  primitive: `+` is add, `-` sub, `*` mul, `/` div, `%` mod, `<` lt,
  `==` eq and `::` cons. Everything else, including `dc`, is written as
  a call.

  Comments start with `#` and run to the end of the line. Strings accept
  the escapes `\\"`, `\\\\`, `\\n` and `\\t`.

  Errors carry the 1-based line and column of the token where the
  problem was found.
  """

  @type form :: integer | boolean | String.t() | atom | [form]
  @type error :: {pos_integer, pos_integer, String.t()}

  @doc """
  Parses `source` into a list of top-level forms.
  """
  @spec parse(String.t()) :: {:ok, [form]} | {:error, error}
  def parse(source) when is_binary(source) do
    with {:ok, tokens, end_loc} <- :thunk_lexer.string(String.to_charlist(source), {1, 1}),
         {:ok, forms} <- :thunk_parser.parse(tokens ++ [{:"$end", end_loc}]) do
      {:ok, forms}
    else
      {:error, {{line, col}, module, reason}, _end} ->
        {:error, {line, col, message(module, reason)}}

      {:error, {{line, col}, module, reason}} ->
        {:error, {line, col, message(module, reason)}}
    end
  end

  @doc """
  Like `parse/1` but raises `ArgumentError` on invalid input.
  """
  @spec parse!(String.t()) :: [form]
  def parse!(source) do
    case parse(source) do
      {:ok, forms} ->
        forms

      {:error, {line, col, message}} ->
        raise ArgumentError, "line #{line}, column #{col}: #{message}"
    end
  end

  defp message(:thunk_parser, [_, []]), do: "unexpected end of input"
  defp message(:thunk_lexer, {:user, text}), do: to_string(text)
  defp message(module, reason), do: module.format_error(reason) |> to_string()
end
