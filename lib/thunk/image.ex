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
