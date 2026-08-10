defmodule Thunk.PreludeTest do
  use ExUnit.Case, async: true

  setup_all do
    %{ctx: Thunk.Prelude.load()}
  end

  defp ev(ctx, source, env \\ %{}), do: Thunk.eval(source, ctx, env)

  test "the prelude file exists in priv" do
    assert File.exists?(Thunk.Prelude.path())
  end

  test "fold and length", %{ctx: ctx} do
    assert ev(ctx, "(fold (lambda (acc x) (add acc x)) 0 xs)", %{xs: [1, 2, 3]}) == 6
    assert ev(ctx, "(fold (lambda (acc x) (add acc x)) 0 ())") == 0
    assert ev(ctx, "(length xs)", %{xs: [1, 2, 3]}) == 3
    assert ev(ctx, "(length ())") == 0
  end
end
