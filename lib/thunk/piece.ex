defmodule Thunk.Piece do
  @moduledoc """
  A piece of work together with its return address. This is what sits in
  a worker's deque and what travels to another node when stolen.

  `ref` identifies the piece to its owner, `reply_to` is the process
  waiting for the result, `job` is `{job_id, origin_node}` or nil for a
  piece that only needs the prelude.
  """

  alias Thunk.Work

  @enforce_keys [:work, :ref, :reply_to]
  defstruct [:work, :ref, :reply_to, job: nil]

  @type t :: %__MODULE__{
          work: Work.t(),
          ref: reference,
          reply_to: pid,
          job: nil | {reference, node}
        }
end
