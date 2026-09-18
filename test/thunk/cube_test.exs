defmodule Thunk.CubeTest do
  use ExUnit.Case, async: true

  alias Thunk.Image
  alias Thunk.Scheduler.{Local, Sequential}

  @main "(def main (lambda (dims) (render (head dims) (head (tail dims)) (lambda (rows) (lt (length rows) 4)))))"

  setup_all do
    program = File.read!(Path.join(:code.priv_dir(:thunk), "demos/cube.thunk")) <> @main
    %{ctx: Thunk.load(program, Thunk.Prelude.load())}
  end

  defp ev(ctx, source, env \\ %{}), do: Thunk.eval(source, ctx, env)

  test "prelude helpers used by the renderer", %{ctx: ctx} do
    assert ev(ctx, "(range 0 4)") == [0, 1, 2, 3]
    assert ev(ctx, "(range 2 2)") == []
    assert ev(ctx, "(max 3 5)") == 5
    assert ev(ctx, "(min 3 5)") == 3

    for n <- [0, 1, 2, 3, 4, 15, 16, 17, 99, 100, 123_456_789, 10_000_000_000] do
      assert ev(ctx, "(isqrt n)", %{n: n}) == :math.sqrt(n) |> floor()
    end
  end

  test "fixed point vectors", %{ctx: ctx} do
    assert ev(ctx, "(fx-mul (fx 3) (fx 2))") == 6 * 4096
    assert ev(ctx, "(fx-div (fx 3) (fx 2))") == div(3 * 4096, 2)
    assert ev(ctx, "(v-dot (vec one 0 0) (vec one 0 0))") == 4096
    assert ev(ctx, "(v-cross (vec one 0 0) (vec 0 one 0))") == [0, 0, 4096]
    assert ev(ctx, "(v-len (vec (fx 3) (fx 4) 0))") == 5 * 4096
    assert ev(ctx, "(v-len (v-norm (vec (fx 3) (fx 4) (fx 12))))") in 4090..4096
  end

  test "sequential and local schedulers render the same image", %{ctx: ctx} do
    seq = Thunk.run(Thunk.with_scheduler(ctx, Sequential), [32, 24])
    local = Thunk.run(Thunk.with_scheduler(ctx, Local), [32, 24])
    assert seq == local
    assert length(seq) == 24
    assert Enum.all?(seq, &(length(&1) == 32))
    assert Enum.all?(List.flatten(seq), &(&1 in 0..255))
  end

  test "the cube is lit in the middle and the corners are background", %{ctx: ctx} do
    rows = Thunk.run(Thunk.with_scheduler(ctx, Sequential), [32, 24])
    centre = rows |> Enum.at(12) |> Enum.at(16)
    corner = rows |> Enum.at(0) |> Enum.at(0)
    assert centre > 100
    assert corner < 80
  end

  test "bmp encoding" do
    rows = [[0, 128, 255], [255, 128, 0]]
    bmp = Image.bmp(rows)
    # 3 pixels of 3 bytes padded to 12 bytes per row, two rows, 54 byte header
    assert byte_size(bmp) == 54 + 2 * 12
    assert <<"BM", size::little-32, _::binary>> = bmp
    assert size == byte_size(bmp)
    # bottom row first, blue green red per pixel
    assert binary_part(bmp, 54, 9) == <<255, 255, 255, 128, 128, 128, 0, 0, 0>>
  end

  test "ascii preview" do
    rows = for j <- 0..7, do: for(_ <- 0..15, do: j * 32)
    # 16 columns into 8 means every second pixel, and every fourth row
    lines = Image.ascii(rows, 8)
    assert length(lines) == 2
    assert Enum.all?(lines, &(String.length(&1) == 8))
    assert hd(lines) != List.last(lines)
  end
end
