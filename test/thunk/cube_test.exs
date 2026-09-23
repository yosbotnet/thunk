defmodule Thunk.CubeTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Thunk.Image
  alias Thunk.Scheduler.{Local, Sequential}

  @main "def main(dims) = render(head(dims), head(tail(dims)), head(tail(tail(dims))), fn(rows) -> length(rows) < 4)"

  # The orbit angle that puts the camera at (3, 2.2, 4), atan(4/3).
  @angle 3798

  setup_all do
    program = File.read!(Path.join(:code.priv_dir(:thunk), "demos/cube.thunk")) <> @main
    %{ctx: Thunk.load(program, Thunk.Prelude.load())}
  end

  defp ev(ctx, source, env \\ %{}), do: Thunk.eval(source, ctx, env)

  defp render(ctx, scheduler, w, h, angle) do
    Thunk.run(Thunk.with_scheduler(ctx, scheduler), [w, h, angle])
  end

  test "prelude helpers used by the renderer", %{ctx: ctx} do
    assert ev(ctx, "range(0, 4)") == [0, 1, 2, 3]
    assert ev(ctx, "range(2, 2)") == []
    assert ev(ctx, "max(3, 5)") == 5
    assert ev(ctx, "min(3, 5)") == 3

    for n <- [0, 1, 2, 3, 4, 15, 16, 17, 99, 100, 123_456_789, 10_000_000_000] do
      assert ev(ctx, "isqrt(n)", %{n: n}) == :math.sqrt(n) |> floor()
    end
  end

  test "fixed point vectors", %{ctx: ctx} do
    assert ev(ctx, "fx_mul(fx(3), fx(2))") == 6 * 4096
    assert ev(ctx, "fx_div(fx(3), fx(2))") == div(3 * 4096, 2)
    assert ev(ctx, "v_dot(vec(one, 0, 0), vec(one, 0, 0))") == 4096
    assert ev(ctx, "v_cross(vec(one, 0, 0), vec(0, one, 0))") == [0, 0, 4096]
    assert ev(ctx, "v_len(vec(fx(3), fx(4), 0))") == 5 * 4096
    assert ev(ctx, "v_len(v_norm(vec(fx(3), fx(4), fx(12))))") in 4090..4096
  end

  test "sine and cosine in fixed point", %{ctx: ctx} do
    for degrees <- Enum.take_every(-360..720, 15) do
      radians = degrees * :math.pi() / 180
      angle = round(radians * 4096)
      assert_in_delta ev(ctx, "sin(a)", %{a: angle}) / 4096, :math.sin(radians), 0.01
      assert_in_delta ev(ctx, "cos(a)", %{a: angle}) / 4096, :math.cos(radians), 0.01
    end
  end

  test "the camera orbits at constant distance", %{ctx: ctx} do
    for angle <- [0, 3798, 10_000, 20_000] do
      eye = ev(ctx, "eye_at(a)", %{a: angle})
      assert_in_delta ev(ctx, "v_len(e)", %{e: eye}) / 4096, :math.sqrt(25 + 2.2 * 2.2), 0.02
    end

    assert ev(ctx, "eye_at(a)", %{a: @angle})
           |> Enum.map(&(&1 / 4096))
           |> Enum.map(&Float.round(&1, 1)) ==
             [3.0, 2.2, 4.0]
  end

  test "sequential and local schedulers render the same image", %{ctx: ctx} do
    seq = render(ctx, Sequential, 32, 24, @angle)
    local = render(ctx, Local, 32, 24, @angle)
    assert seq == local
    assert length(seq) == 24
    assert Enum.all?(seq, &(length(&1) == 32))
    assert Enum.all?(List.flatten(seq), &(&1 in 0..255))
  end

  test "the cube is lit in the middle and the corners are background", %{ctx: ctx} do
    rows = render(ctx, Sequential, 32, 24, @angle)
    centre = rows |> Enum.at(12) |> Enum.at(16)
    corner = rows |> Enum.at(0) |> Enum.at(0)
    assert centre > 100
    assert corner < 80
  end

  test "different angles give different frames with the cube still in view", %{ctx: ctx} do
    a = render(ctx, Sequential, 32, 24, @angle)
    b = render(ctx, Sequential, 32, 24, @angle + 6434)
    assert a != b
    # The centre is in shadow at this angle.
    assert b |> Enum.at(12) |> Enum.at(16) != 16 + div(48 * 12, 24)
    assert Enum.max(List.flatten(b)) > 150
  end

  test "bmp encoding" do
    rows = [[0, 128, 255], [255, 128, 0]]
    bmp = Image.bmp(rows)
    # Each BMP row is padded to 12 bytes.
    assert byte_size(bmp) == 54 + 2 * 12
    assert <<"BM", size::little-32, _::binary>> = bmp
    assert size == byte_size(bmp)
    # BMP stores the bottom row first, in BGR order.
    assert binary_part(bmp, 54, 9) == <<255, 255, 255, 128, 128, 128, 0, 0, 0>>
  end

  test "gif encoding round trips through a nine-bit decoder" do
    frame1 = for j <- 0..3, do: for(i <- 0..299, do: rem(i + j, 256))
    frame2 = Enum.map(frame1, &Enum.reverse/1)
    gif = Image.gif([frame1, frame2], 5)

    assert <<"GIF89a", 300::little-16, 4::little-16, 0xF7, 0, 0, _::binary>> = gif
    assert :binary.last(gif) == 0x3B

    # Skip the GIF header, palette and loop extension.
    rest = binary_part(gif, 13 + 768 + 19, byte_size(gif) - 13 - 768 - 19)
    {pixels1, rest} = decode_frame(rest)
    {pixels2, <<0x3B>>} = decode_frame(rest)
    assert pixels1 == List.flatten(frame1)
    assert pixels2 == List.flatten(frame2)
  end

  test "ascii preview" do
    rows = for j <- 0..7, do: for(_ <- 0..15, do: j * 32)
    lines = Image.ascii(rows, 8)
    assert length(lines) == 2
    assert Enum.all?(lines, &(String.length(&1) == 8))
    assert hd(lines) != List.last(lines)
  end

  # Enough GIF decoding to check the frames written above.
  defp decode_frame(
         <<0x21, 0xF9, 4, _::binary-size(4), 0, 0x2C, _::binary-size(9), 8, rest::binary>>
       ) do
    {data, rest} = sub_blocks(rest, [])

    pixels =
      data
      |> :binary.bin_to_list()
      |> Enum.reduce({0, 0, []}, fn byte, {buffer, bits, codes} ->
        take_codes(bor(buffer, bsl(byte, bits)), bits + 8, codes)
      end)
      |> elem(2)
      |> Enum.reverse()
      |> Enum.reject(&(&1 >= 256))

    {pixels, rest}
  end

  defp take_codes(buffer, bits, codes) when bits >= 9 do
    take_codes(bsr(buffer, 9), bits - 9, [band(buffer, 0x1FF) | codes])
  end

  defp take_codes(buffer, bits, codes), do: {buffer, bits, codes}

  defp sub_blocks(<<0, rest::binary>>, acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), rest}

  defp sub_blocks(<<n, chunk::binary-size(n), rest::binary>>, acc),
    do: sub_blocks(rest, [chunk | acc])
end
