defmodule Thunk.Prelude do
  @moduledoc """
  The standard library, written in the language itself and shipped in
  priv/prelude.thunk. Every node loads the same file, so a piece of work
  can refer to prelude functions by name wherever it is evaluated.
  """

  alias Thunk.Context

  @spec path() :: String.t()
  def path, do: Path.join(to_string(:code.priv_dir(:thunk)), "prelude.thunk")

  @spec load(Context.t()) :: Context.t()
  def load(%Context{} = ctx \\ %Context{}) do
    Thunk.load(File.read!(path()), ctx)
  end
end
