defmodule Thunk.Parser do
  @moduledoc """
  Reader for Thunk source code.

  A program is a sequence of S-expressions. The reader turns the text into
  plain Elixir data that the evaluator works on directly: there is no
  separate syntax tree, the S-expression itself is the program.

      form    = integer | boolean | string | symbol | list
      integer = ["-"] digit+
      boolean = "true" | "false"
      string  = '"' (character | escape)* '"'    escapes: \\" \\\\ \\n \\t
      symbol  = run of characters without whitespace, ( ) " or ;
      list    = "(" form* ")"

  Comments start with ";" and run to the end of the line. Space, tab,
  carriage return and newline separate tokens. A string may contain a
  literal newline.

  Mapping to Elixir: integers and booleans map to themselves, strings to
  binaries, symbols to atoms and lists to lists.

  Errors carry the 1-based line and column of the offending character. For
  unterminated constructs (missing ")" or closing quote) the position is the
  one just past the last character of the input.
  """

  @type form :: integer | boolean | String.t() | atom | [form]
  @type error :: {pos_integer, pos_integer, String.t()}

  @delimiters [?\s, ?\t, ?\r, ?\n, ?(, ?), ?", ?;]

  @doc """
  Parses every top-level form in `source`.
  """
  @spec parse(String.t()) :: {:ok, [form]} | {:error, error}
  def parse(source) when is_binary(source) do
    top({source, 1, 1}, [])
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

  defp top(state, acc) do
    case next(state) do
      {:ok, :eof, _pos, _state} ->
        {:ok, Enum.reverse(acc)}

      {:ok, :close, {line, col}, _state} ->
        {:error, {line, col, "unexpected )"}}

      {:ok, token, pos, state} ->
        with {:ok, form, state} <- form(token, pos, state), do: top(state, [form | acc])

      {:error, _} = error ->
        error
    end
  end

  defp form(:open, _pos, state), do: list(state, [])
  defp form({:value, value}, _pos, state), do: {:ok, value, state}
  defp form(:eof, {line, col}, _state), do: {:error, {line, col, "unexpected end of input"}}

  defp list(state, acc) do
    case next(state) do
      {:ok, :close, _pos, state} ->
        {:ok, Enum.reverse(acc), state}

      {:ok, token, pos, state} ->
        with {:ok, form, state} <- form(token, pos, state), do: list(state, [form | acc])

      {:error, _} = error ->
        error
    end
  end

  defp next({"", line, col}), do: {:ok, :eof, {line, col}, {"", line, col}}
  defp next({"\n" <> rest, line, _col}), do: next({rest, line + 1, 1})

  defp next({<<c, rest::binary>>, line, col}) when c in [?\s, ?\t, ?\r],
    do: next({rest, line, col + 1})

  defp next({";" <> rest, line, col}), do: next(comment(rest, line, col + 1))
  defp next({"(" <> rest, line, col}), do: {:ok, :open, {line, col}, {rest, line, col + 1}}
  defp next({")" <> rest, line, col}), do: {:ok, :close, {line, col}, {rest, line, col + 1}}
  defp next({"\"" <> rest, line, col}), do: string(rest, line, col + 1, [], {line, col})
  defp next({src, line, col}), do: symbol(src, line, col, [], {line, col})

  defp comment("\n" <> _ = rest, line, col), do: {rest, line, col}
  defp comment("", line, col), do: {"", line, col}
  defp comment(<<_::utf8, rest::binary>>, line, col), do: comment(rest, line, col + 1)

  defp string("", line, col, _buf, _start), do: {:error, {line, col, "unterminated string"}}

  defp string("\"" <> rest, line, col, buf, start),
    do: {:ok, {:value, to_text(buf)}, start, {rest, line, col + 1}}

  defp string(<<?\\, c, rest::binary>>, line, col, buf, start) when c in [?", ?\\, ?n, ?t],
    do: string(rest, line, col + 2, [unescape(c) | buf], start)

  defp string(<<?\\, _, _::binary>>, line, col, _buf, _start),
    do: {:error, {line, col, "invalid escape"}}

  defp string("\n" <> rest, line, _col, buf, start),
    do: string(rest, line + 1, 1, [?\n | buf], start)

  defp string(<<c::utf8, rest::binary>>, line, col, buf, start),
    do: string(rest, line, col + 1, [c | buf], start)

  defp unescape(?n), do: ?\n
  defp unescape(?t), do: ?\t
  defp unescape(c), do: c

  defp symbol(<<c::utf8, rest::binary>>, line, col, buf, start) when c not in @delimiters,
    do: symbol(rest, line, col + 1, [c | buf], start)

  defp symbol(rest, line, col, buf, start),
    do: {:ok, {:value, classify(to_text(buf))}, start, {rest, line, col}}

  defp to_text(buf), do: buf |> Enum.reverse() |> List.to_string()

  defp classify("true"), do: true
  defp classify("false"), do: false

  defp classify(text) do
    if Regex.match?(~r/\A-?[0-9]+\z/, text) do
      String.to_integer(text)
    else
      String.to_atom(text)
    end
  end
end
