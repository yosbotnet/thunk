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

  describe "what the parallel library puts in a piece" do
    # Hands every piece to the test process before solving it
    # sequentially, so the test can look at what would be sent to a thief.
    defmodule Recorder do
      @behaviour Thunk.Scheduler
      @impl true
      def solve(work, ctx) do
        send(self(), {:work, work})
        Thunk.Scheduler.Sequential.solve(work, ctx)
      end
    end

    setup %{ctx: ctx} do
      program = """
      (def square (lambda (x) (mul x x)))
      (def small? (lambda (v) (lt (length v) 1000)))
      (def main-map (lambda (xs) (pmap square xs small?)))
      (def main-reduce (lambda (xs) (reduce add xs small?)))
      """

      %{rec: Thunk.load(program, Thunk.with_scheduler(ctx, Recorder))}
    end

    defp piece_size(work) do
      [work.pred, work.split, work.base, work.merge] |> :erlang.term_to_binary() |> byte_size()
    end

    test "pmap does not capture the input list in its base case", %{rec: rec} do
      xs = Enum.to_list(1..20_000)
      assert ev(rec, "(main-map xs)", %{xs: xs}) == Enum.map(xs, &(&1 * &1))
      assert_received {:work, work}
      assert piece_size(work) < 2_000
    end

    test "reduce does not capture the input list in its base case", %{rec: rec} do
      xs = Enum.to_list(1..20_000)
      assert ev(rec, "(main-reduce xs)", %{xs: xs}) == Enum.sum(xs)
      assert_received {:work, work}
      assert piece_size(work) < 2_000
    end
  end

  describe "sorting" do
    test "insert and insertion-sort", %{ctx: ctx} do
      assert ev(ctx, "(insert 2 xs)", %{xs: [1, 3]}) == [1, 2, 3]
      assert ev(ctx, "(insert 0 ())") == [0]
      assert ev(ctx, "(insertion-sort xs)", %{xs: [3, 1, 2, 1]}) == [1, 1, 2, 3]
      assert ev(ctx, "(insertion-sort ())") == []
    end

    test "merge-sorted", %{ctx: ctx} do
      assert ev(ctx, "(merge-sorted xs ys)", %{xs: [1, 4, 9], ys: [2, 3, 10]}) ==
               [1, 2, 3, 4, 9, 10]

      assert ev(ctx, "(merge-sorted () ys)", %{ys: [1]}) == [1]
      assert ev(ctx, "(merge-sorted xs ())", %{xs: [1]}) == [1]
      assert ev(ctx, "(merge-sorted xs ys)", %{xs: [1, 1], ys: [1]}) == [1, 1, 1]
    end
  end

  describe "strings and counting" do
    test "split-words on codepoints", %{ctx: ctx} do
      assert ev(ctx, "(split-words (chars s))", %{s: "the  quick\nbrown\tfox "}) ==
               ["the", "quick", "brown", "fox"]

      assert ev(ctx, "(split-words (chars s))", %{s: ""}) == []
      assert ev(ctx, "(split-words (chars s))", %{s: "   "}) == []
      assert ev(ctx, "(split-words (chars s))", %{s: "città"}) == ["città"]
    end

    test "association lists", %{ctx: ctx} do
      al = [["a", 1], ["b", 2]]
      assert ev(ctx, "(assoc-get k al 0)", %{k: "b", al: al}) == 2
      assert ev(ctx, "(assoc-get k al 0)", %{k: "z", al: al}) == 0
      assert ev(ctx, "(assoc-inc k 1 al)", %{k: "a", al: al}) == [["a", 2], ["b", 2]]
      assert ev(ctx, "(assoc-inc k 5 al)", %{k: "c", al: al}) == [["a", 1], ["b", 2], ["c", 5]]

      assert ev(ctx, "(assoc-merge a b)", %{a: al, b: [["b", 1], ["c", 1]]}) ==
               [["a", 1], ["b", 3], ["c", 1]]
    end

    test "count-words", %{ctx: ctx} do
      assert ev(ctx, "(count-words ws)", %{ws: ["a", "b", "a"]}) == [["a", 2], ["b", 1]]
    end
  end
end
