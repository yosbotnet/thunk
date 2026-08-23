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

  describe "list library" do
    test "reverse and append", %{ctx: ctx} do
      assert ev(ctx, "(reverse xs)", %{xs: [1, 2, 3]}) == [3, 2, 1]
      assert ev(ctx, "(reverse ())") == []
      assert ev(ctx, "(append xs ys)", %{xs: [1, 2], ys: [3]}) == [1, 2, 3]
      assert ev(ctx, "(append () ys)", %{ys: [3]}) == [3]
      assert ev(ctx, "(append xs ())", %{xs: [1]}) == [1]
    end

    test "map and filter keep order", %{ctx: ctx} do
      assert ev(ctx, "(map (lambda (x) (mul x x)) xs)", %{xs: [1, 2, 3]}) == [1, 4, 9]
      assert ev(ctx, "(map (lambda (x) x) ())") == []
      assert ev(ctx, "(filter (lambda (x) (lt x 3)) xs)", %{xs: [5, 1, 4, 2]}) == [1, 2]
    end

    test "take, drop and split-at", %{ctx: ctx} do
      assert ev(ctx, "(take 2 xs)", %{xs: [1, 2, 3]}) == [1, 2]
      assert ev(ctx, "(take 5 xs)", %{xs: [1, 2, 3]}) == [1, 2, 3]
      assert ev(ctx, "(take 0 xs)", %{xs: [1, 2, 3]}) == []
      assert ev(ctx, "(drop 2 xs)", %{xs: [1, 2, 3]}) == [3]
      assert ev(ctx, "(drop 5 xs)", %{xs: [1, 2, 3]}) == []
      assert ev(ctx, "(split-at 1 xs)", %{xs: [1, 2, 3]}) == [[1], [2, 3]]
    end

    test "halves splits at the middle, smaller half first", %{ctx: ctx} do
      assert ev(ctx, "(halves xs)", %{xs: [1, 2, 3, 4]}) == [[1, 2], [3, 4]]
      assert ev(ctx, "(halves xs)", %{xs: [1, 2, 3]}) == [[1], [2, 3]]
      assert ev(ctx, "(halves xs)", %{xs: [1]}) == [[], [1]]
      assert ev(ctx, "(halves ())") == [[], []]
    end
  end

  describe "parallel library" do
    @small "(lambda (v) (lt (length v) 3))"

    test "pmap equals map", %{ctx: ctx} do
      xs = Enum.to_list(1..20)

      assert ev(ctx, "(pmap (lambda (x) (mul x 2)) xs #{@small})", %{xs: xs}) ==
               Enum.map(xs, &(&1 * 2))

      assert ev(ctx, "(pmap (lambda (x) x) () #{@small})") == []
    end

    test "reduce equals fold for an associative operation", %{ctx: ctx} do
      xs = Enum.to_list(1..50)
      assert ev(ctx, "(reduce add xs #{@small})", %{xs: xs}) == Enum.sum(xs)
      assert ev(ctx, "(reduce add xs #{@small})", %{xs: [7]}) == 7
    end

    test "pmap and reduce give the same answer under the local scheduler", %{ctx: ctx} do
      local = Thunk.with_scheduler(ctx, Thunk.Scheduler.Local)
      xs = Enum.to_list(1..100)

      assert ev(
               local,
               "(reduce add (pmap (lambda (x) (mul x x)) xs #{@small}) #{@small})",
               %{xs: xs}
             ) == Enum.sum(Enum.map(xs, &(&1 * &1)))
    end
  end
end
