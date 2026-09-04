defmodule Thunk.Scheduler.Distributed do
  @moduledoc false

  alias Thunk.Piece

  @spec run_piece(Piece.t()) :: no_return
  def run_piece(%Piece{}), do: raise("not implemented")
end
