defmodule Thunk.Work do
  @moduledoc """
  One piece of divide-and-conquer work: a value and the four functions
  that decide whether it is small enough, split it, solve it directly
  and combine two results. All fields are plain language values, so a
  piece can be sent to any process or node that has loaded the same
  definitions.
  """

  @enforce_keys [:value, :pred, :split, :base, :merge]
  defstruct [:value, :pred, :split, :base, :merge]

  @type t :: %__MODULE__{value: term, pred: term, split: term, base: term, merge: term}
end
