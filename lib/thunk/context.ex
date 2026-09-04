defmodule Thunk.Context do
  @moduledoc """
  What evaluation needs besides the local environment: the table of
  top-level definitions and the scheduler that handles dc.

  `job` identifies the distributed job a piece belongs to, as
  `{id, origin_node}`, so that a node meeting the piece can fetch the
  job's definitions from the origin. It is nil outside distributed jobs.
  """

  defstruct defs: %{}, scheduler: Thunk.Scheduler.Sequential, job: nil

  @type job :: nil | {reference, node}
  @type t :: %__MODULE__{defs: %{atom => term}, scheduler: module, job: job}
end
