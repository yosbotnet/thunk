defmodule Thunk.DemoTest do
  use ExUnit.Case, async: true

  alias Thunk.Scheduler.{Local, Sequential}

  setup_all do
    %{ctx: Thunk.Prelude.load()}
  end

  @schedulers [Sequential, Local]

  # Enum.take on an infinite stream, because 1..0 is a decreasing range
  # in Elixir and would produce two elements instead of none.
  defp random_list do
    Stream.repeatedly(fn -> Enum.random(-50..50) end) |> Enum.take(Enum.random(0..200))
  end

  defp random_text do
    words = ~w(the quick brown fox jumps over lazy dog città 日本)

    Stream.repeatedly(fn -> Enum.random(words) end)
    |> Enum.take(Enum.random(0..300))
    |> Enum.join(" ")
  end

  test "mergesort agrees with Enum.sort under every scheduler", %{ctx: ctx} do
    for scheduler <- @schedulers, _ <- 1..10 do
      xs = random_list()
      ctx = Thunk.with_scheduler(ctx, scheduler)

      assert Thunk.eval("(mergesort xs (lambda (v) (lt (length v) 8)))", ctx, %{xs: xs}) ==
               Enum.sort(xs)
    end
  end

  test "word-count agrees with a native count under every scheduler", %{ctx: ctx} do
    for scheduler <- @schedulers, _ <- 1..10 do
      text = random_text()
      ctx = Thunk.with_scheduler(ctx, scheduler)

      result =
        Thunk.eval("(word-count text (lambda (v) (lt (length v) 16)))", ctx, %{text: text})

      expected = text |> String.split() |> Enum.frequencies()
      assert Map.new(result, fn [word, n] -> {word, n} end) == expected
      assert length(result) == map_size(expected)
    end
  end

  test "a program file with a main runs end to end", %{ctx: ctx} do
    program = """
    (def main (lambda (xs) (mergesort xs (lambda (v) (lt (length v) 4)))))
    """

    ctx = Thunk.load(program, Thunk.with_scheduler(ctx, Local))
    assert Thunk.run(ctx, [3, 1, 2]) == [1, 2, 3]
  end
end
