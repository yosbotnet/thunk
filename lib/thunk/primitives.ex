defmodule Thunk.Primitives do
  @moduledoc """
  The operations the language cannot express by itself. Everything else
  is written in the language, in the prelude.

  Integers: add sub mul div mod lt eq. Lists: cons head tail nil?.
  Strings: chars turns a string into its codepoints, string does the
  reverse. div truncates toward zero, mod takes the sign of the divisor.
  """

  alias Thunk.Error

  @names [:add, :sub, :mul, :div, :mod, :lt, :eq, :cons, :head, :tail, :nil?, :chars, :string]

  @spec names() :: [atom]
  def names, do: @names

  @spec lookup(atom) :: {:ok, {:primitive, atom}} | :error
  def lookup(name) when name in @names, do: {:ok, {:primitive, name}}
  def lookup(_name), do: :error

  @spec call(atom, [term]) :: term
  def call(:add, [a, b]) when is_integer(a) and is_integer(b), do: a + b
  def call(:sub, [a, b]) when is_integer(a) and is_integer(b), do: a - b
  def call(:mul, [a, b]) when is_integer(a) and is_integer(b), do: a * b
  def call(:div, [a, b]) when is_integer(a) and is_integer(b) and b != 0, do: div(a, b)
  def call(:mod, [a, b]) when is_integer(a) and is_integer(b) and b != 0, do: Integer.mod(a, b)
  def call(:lt, [a, b]) when is_integer(a) and is_integer(b), do: a < b
  def call(:eq, [a, b]), do: a == b
  def call(:cons, [x, xs]) when is_list(xs), do: [x | xs]
  def call(:head, [[x | _]]), do: x
  def call(:tail, [[_ | xs]]), do: xs
  def call(:nil?, [x]), do: x == []
  def call(:chars, [s]) when is_binary(s), do: String.to_charlist(s)

  def call(:string, [cs]) when is_list(cs) do
    List.to_string(cs)
  rescue
    e in [ArgumentError, UnicodeConversionError] ->
      raise Error, "string: not a list of codepoints: #{inspect(cs)} (#{Exception.message(e)})"
  end

  def call(name, args) do
    raise Error, "bad arguments to #{name}: #{inspect(args)}"
  end
end
