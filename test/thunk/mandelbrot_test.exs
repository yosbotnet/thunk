defmodule Thunk.MandelbrotTest do
  use ExUnit.Case, async: true

  alias Thunk.Scheduler.{Local, Sequential}

  @main "def main(d) = render(head(d), head(tail(d)), head(tail(tail(d))), fn(rows) -> length(rows) < 4)"

  setup_all do
    program = File.read!(Path.join(:code.priv_dir(:thunk), "demos/mandelbrot.thunk")) <> @main
    %{ctx: Thunk.load(program, Thunk.Prelude.load())}
  end

  defp ev(ctx, source, env \\ %{}), do: Thunk.eval(source, ctx, env)

  test "points inside the set reach the iteration limit", %{ctx: ctx} do
    # the origin and -1 are in the set
    assert ev(ctx, "escape_time(0, 0, 50)") == 50
    assert ev(ctx, "escape_time(-one, 0, 50)") == 50
  end

  test "points outside the set escape, far ones immediately", %{ctx: ctx} do
    assert ev(ctx, "escape_time(2 * one, 2 * one, 50)") <= 1
    n = ev(ctx, "escape_time(one / 2, one / 2, 50)")
    assert n > 1 and n < 50
  end

  test "escape time agrees with a floating point version away from the boundary", %{ctx: ctx} do
    float_escape = fn cr, ci, max ->
      Enum.reduce_while(0..max, {0.0, 0.0}, fn n, {zr, zi} ->
        cond do
          n == max -> {:halt, max}
          zr * zr + zi * zi > 4.0 -> {:halt, n}
          true -> {:cont, {zr * zr - zi * zi + cr, 2 * zr * zi + ci}}
        end
      end)
    end

    for {cr, ci} <- [{-0.1, 0.1}, {0.4, 0.4}, {-1.9, 0.3}, {0.3, -0.6}, {-0.75, 0.3}] do
      fixed = ev(ctx, "escape_time(a, b, 60)", %{a: round(cr * 65536), b: round(ci * 65536)})
      assert abs(fixed - float_escape.(cr, ci, 60)) <= 1
    end
  end

  test "sequential and local schedulers render the same image", %{ctx: ctx} do
    seq = Thunk.run(Thunk.with_scheduler(ctx, Sequential), [32, 24, 40])
    local = Thunk.run(Thunk.with_scheduler(ctx, Local), [32, 24, 40])
    assert seq == local
    assert length(seq) == 24
    assert Enum.all?(seq, &(length(&1) == 32))
    assert Enum.all?(List.flatten(seq), &(&1 in 0..255))
  end

  test "the set is dark in the middle and the corners are light", %{ctx: ctx} do
    rows = Thunk.run(Thunk.with_scheduler(ctx, Sequential), [64, 48, 60])
    # the middle of the view, near -0.7, lies inside the main cardioid
    assert rows |> Enum.at(24) |> Enum.at(31) < 20
    assert rows |> Enum.at(0) |> Enum.at(0) > 20
  end
end
