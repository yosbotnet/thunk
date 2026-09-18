defmodule Mix.Tasks.Thunk.Demo do
  @shortdoc "Runs the mergesort or word count demo and reports timings"

  @moduledoc """
  Runs a demo job and prints, for each repetition, the elapsed time, a
  check against a native Elixir computation, and the steal counters of
  every node.

      mix thunk.demo mergesort --size 20000 --threshold 500 --repeat 3
      mix thunk.demo wordcount --size 20000 --threshold 500

  Options: --size (elements or words, default 10000), --threshold (pieces
  smaller than this are solved directly, default 500), --repeat (default
  1), --seed (default 1), --scheduler sequential|local|distributed
  (default distributed), --limit (evaluators this node may run itself,
  default 0 for distributed so that all work goes to the peers), --wait
  (seconds to wait for at least one peer, default 10).
  """

  use Mix.Task

  alias Thunk.{Cluster, Worker}

  @switches [
    size: :integer,
    threshold: :integer,
    repeat: :integer,
    seed: :integer,
    scheduler: :string,
    limit: :integer,
    wait: :integer
  ]

  @impl true
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, strict: @switches)

    demo =
      case rest do
        ["mergesort"] -> :mergesort
        ["wordcount"] -> :wordcount
        _ -> Mix.raise("usage: mix thunk.demo mergesort|wordcount [options]")
      end

    Mix.Task.run("app.start")

    size = opts[:size] || 10_000
    threshold = opts[:threshold] || 500
    repeat = opts[:repeat] || 1
    seed = opts[:seed] || 1
    scheduler = String.to_atom(opts[:scheduler] || "distributed")

    ctx = context(demo, threshold, scheduler)

    if scheduler == :distributed do
      Worker.set_limit(opts[:limit] || 0)

      case Cluster.wait_for_peers(1, (opts[:wait] || 10) * 1_000) do
        :ok -> Mix.shell().info("peers: #{inspect(Node.list())}")
        :timeout -> Mix.shell().info("no peers connected, running on this node only")
      end
    end

    for i <- 1..repeat do
      input = input(demo, size, seed + i)
      {micros, result} = :timer.tc(fn -> Thunk.run(ctx, input) end)
      ok = if check(demo, input, result), do: "ok", else: "MISMATCH"

      Mix.shell().info(
        "run #{i}: #{demo} size=#{size} threshold=#{threshold} #{ok} #{div(micros, 1000)} ms"
      )

      for node <- [node() | Node.list()] do
        s = Worker.stats(node)

        Mix.shell().info(
          "  #{node}: steals=#{s.steals} stolen_from=#{s.stolen_from} evaluated=#{s.evaluated}"
        )
      end
    end
  end

  defp context(demo, threshold, :distributed), do: Cluster.load(program(demo, threshold))

  defp context(demo, threshold, scheduler) do
    module =
      case scheduler do
        :sequential -> Thunk.Scheduler.Sequential
        :local -> Thunk.Scheduler.Local
        other -> Mix.raise("unknown scheduler #{other}")
      end

    Thunk.load(program(demo, threshold), Thunk.with_scheduler(Worker.prelude(), module))
  end

  defp program(:mergesort, t),
    do: "(def main (lambda (xs) (mergesort xs (lambda (v) (lt (length v) #{t})))))"

  defp program(:wordcount, t),
    do: "(def main (lambda (text) (word-count text (lambda (v) (lt (length v) #{t})))))"

  defp input(:mergesort, size, seed) do
    :rand.seed(:exsss, {seed, seed, seed})
    for _ <- 1..size, do: :rand.uniform(1_000_000)
  end

  defp input(:wordcount, size, seed) do
    :rand.seed(:exsss, {seed, seed, seed})
    words = ~w(alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu)
    Enum.map_join(1..size, " ", fn _ -> Enum.random(words) end)
  end

  defp check(:mergesort, input, result), do: result == Enum.sort(input)

  defp check(:wordcount, input, result) do
    Map.new(result, fn [w, n] -> {w, n} end) == Enum.frequencies(String.split(input))
  end
end
