defmodule Thunk.Context do
  @moduledoc """
  What evaluation needs besides the local environment: the table of
  top-level definitions and the scheduler that handles dc.
  """

  defstruct defs: %{}, scheduler: Thunk.Scheduler.Sequential

  @type t :: %__MODULE__{defs: %{atom => term}, scheduler: module}
end
