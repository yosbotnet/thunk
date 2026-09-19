defmodule Thunk.Image do
  @moduledoc """
  Turns an image computed by a job, a list of rows of grey levels from 0
  to 255 with the top row first, into a BMP file or a text preview.
  """

  @doc """
  Encodes the rows as an uncompressed 24-bit BMP. Rows are stored bottom
  up and padded to four bytes, as the format requires.
  """
  @spec bmp([[0..255]]) :: binary
  def bmp([first | _] = rows) do
    height = length(rows)
    width = length(first)
    row_size = div(width * 3 + 3, 4) * 4
    data_size = row_size * height
    padding = row_size - width * 3

    header =
      <<"BM", 54 + data_size::little-32, 0::little-16, 0::little-16, 54::little-32, 40::little-32,
        width::little-32, height::little-32, 1::little-16, 24::little-16, 0::little-32,
        data_size::little-32, 2835::little-32, 2835::little-32, 0::little-32, 0::little-32>>

    body =
      rows
      |> Enum.reverse()
      |> Enum.map(fn row ->
        [Enum.map(row, fn v -> <<v, v, v>> end), <<0::size(padding * 8)>>]
      end)

    IO.iodata_to_binary([header, body])
  end

  @doc """
  Encodes a list of frames, each a list of rows like `bmp/1` takes, as
  an animated GIF that loops forever, with `delay` hundredths of a second
  between frames.

  The pixel data is stored without compression: every pixel is emitted
  as its own nine-bit LZW code, with a clear code every 250 pixels so
  that the decoder's table never grows. Larger files, no encoder to get
  wrong.
  """
  @spec gif([[[0..255]]], pos_integer) :: binary
  def gif([[first | _] | _] = frames, delay \\ 10) do
    height = length(hd(frames))
    width = length(first)

    screen = <<"GIF89a", width::little-16, height::little-16, 0xF7, 0, 0>>
    palette = for v <- 0..255, into: <<>>, do: <<v, v, v>>
    loop = <<0x21, 0xFF, 0x0B, "NETSCAPE2.0", 0x03, 0x01, 0::little-16, 0x00>>

    images =
      Enum.map(frames, fn rows ->
        control = <<0x21, 0xF9, 0x04, 0x00, delay::little-16, 0x00, 0x00>>
        descriptor = <<0x2C, 0::little-16, 0::little-16, width::little-16, height::little-16, 0>>
        [control, descriptor, <<8>>, blocks(codes(List.flatten(rows))), <<0>>]
      end)

    IO.iodata_to_binary([screen, palette, loop, images, <<0x3B>>])
  end

  # Nine-bit codes, least significant bit first: a clear code (256)
  # before every run of at most 250 pixels, and the end code (257) last.
  defp codes(pixels) do
    codes =
      pixels
      |> Enum.chunk_every(250)
      |> Enum.flat_map(fn chunk -> [256 | chunk] end)

    pack(codes ++ [257], 0, 0, [])
  end

  defp pack([], buffer, bits, acc) when bits > 0, do: finish([buffer | acc])
  defp pack([], _buffer, _bits, acc), do: finish(acc)

  defp pack([code | rest], buffer, bits, acc) do
    buffer = Bitwise.bor(buffer, Bitwise.bsl(code, bits))
    flush(rest, buffer, bits + 9, acc)
  end

  defp flush(rest, buffer, bits, acc) when bits >= 8 do
    flush(rest, Bitwise.bsr(buffer, 8), bits - 8, [Bitwise.band(buffer, 0xFF) | acc])
  end

  defp flush(rest, buffer, bits, acc), do: pack(rest, buffer, bits, acc)

  defp finish(acc), do: acc |> Enum.reverse() |> :binary.list_to_bin()

  # Data sub-blocks of at most 255 bytes, each preceded by its length.
  defp blocks(<<chunk::binary-size(255), rest::binary>>), do: [255, chunk | blocks(rest)]
  defp blocks(<<>>), do: []
  defp blocks(rest), do: [byte_size(rest), rest]

  @doc """
  A preview of the image as lines of text, at most `columns` wide. Every
  sampled pixel becomes a character from dark to bright; rows are sampled
  twice as sparsely as columns because characters are taller than wide.
  """
  @spec ascii([[0..255]], pos_integer) :: [String.t()]
  def ascii([first | _] = rows, columns \\ 80) do
    ramp = ~c" .:-=+*#%@"
    step = max(1, div(length(first) + columns - 1, columns))

    rows
    |> Enum.take_every(step * 2)
    |> Enum.map(fn row ->
      row
      |> Enum.take_every(step)
      |> Enum.map(fn v -> Enum.at(ramp, div(v * (length(ramp) - 1), 255)) end)
      |> List.to_string()
    end)
  end
end
