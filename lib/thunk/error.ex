defmodule Thunk.Error do
  @moduledoc """
  Raised for every error at the language level: unbound symbols, wrong
  arguments to a primitive, malformed forms, misuse of dc. There are no
  error values in the language, evaluation simply stops.
  """
  defexception [:message]
end
