defmodule Mix.Tasks.Thunk.Demo do
  @shortdoc "Runs the mergesort, word count, cube or Mandelbrot demo and reports timings"

  @moduledoc """
  Runs a demo job and prints, for each repetition, the elapsed time, a
  check of the result, and the steal counters of every node.

      mix thunk.demo mergesort --size 20000 --threshold 500 --repeat 3
      mix thunk.demo wordcount --size 20000 --threshold 500
      mix thunk.demo cube --width 320 --height 240 --threshold 8
      mix thunk.demo mandelbrot --width 640 --height 480 --iterations 200

  Mergesort and word count are checked against native Elixir. The cube
  is a raytraced image (priv/demos/cube.thunk): its rows are checked for
  shape and range, the picture is written to a BMP file (--out, default
  cube.bmp) and previewed in the terminal. The Mandelbrot demo
  (priv/demos/mandelbrot.thunk) is handled the same way; its rows cost
  very different amounts of work, depending on how much of the set they
  cross.

  Options: --size (elements or words, default 10000), --width and
  --height (cube, default 160 by 120), --threshold (pieces smaller than
  this are solved directly: elements, words or rows; default 500, or 8
  for the cube), --repeat (default 1), --seed (default 1), --scheduler
  sequential|local|distributed (default distributed), --limit
  (evaluators this node may run itself, default 0 for distributed so
  that all work goes to the peers), --wait (seconds to wait for at least
  one peer, default 10), --out (cube image path), --frames (cube: render
  this many frames with the camera going once around the cube, each
  frame a job of its own, and write an animated GIF instead of a BMP),
  --iterations (Mandelbrot: iteration limit per pixel, default 200).
  """

  use Mix.Task

  alias Thunk.{Cluster, Image, Worker}

  @switches [
    size: :integer,
    width: :integer,
    height: :integer,
    threshold: :integer,
    repeat: :integer,
    seed: :integer,
    scheduler: :string,
    limit: :integer,
    wait: :integer,
    out: :string,
    frames: :integer,
    iterations: :integer
  ]

  # Orbit angle of the first frame, atan(4/3) in fixed point: the camera
  # at (3, 2.2, 4). Further frames go once around the cube.
  @first_angle 3798
  @two_pi 25736

  @impl true
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, strict: @switches)

    demo =
      case rest do
        ["mergesort"] -> :mergesort
        ["wordcount"] -> :wordcount
        ["cube"] -> :cube
        ["mandelbrot"] -> :mandelbrot
        _ -> Mix.raise("usage: mix thunk.demo mergesort|wordcount|cube|mandelbrot [options]")
      end

    Mix.Task.run("app.start")

    threshold = opts[:threshold] || if(demo in [:cube, :mandelbrot], do: 8, else: 500)
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

    frames = if demo == :cube, do: opts[:frames] || 1, else: 1

    results =
      for i <- 1..repeat, frame <- 0..(frames - 1) do
        input = input(demo, opts, seed + i, frame, frames)
        {micros, result} = :timer.tc(fn -> Thunk.run(ctx, input) end)
        ok = if check(demo, input, result), do: "ok", else: "MISMATCH"

        Mix.shell().info(
          "run #{i}#{if frames > 1, do: " frame #{frame}", else: ""}: #{demo} #{describe(demo, input)} threshold=#{threshold} #{ok} #{div(micros, 1000)} ms"
        )

        for node <- [node() | Node.list()] do
          s = Worker.stats(node)

          Mix.shell().info(
            "  #{node}: steals=#{s.steals} stolen_from=#{s.stolen_from} evaluated=#{s.evaluated} recovered=#{s.recovered}"
          )
        end

        result
      end

    if demo == :mandelbrot, do: save_image(List.last(results), opts[:out] || "mandelbrot.bmp")

    if demo == :cube do
      last = Enum.take(results, -frames)

      case last do
        [rows] -> save_image(rows, opts[:out] || "cube.bmp")
        rows -> save_animation(rows, opts[:out] || "cube.gif")
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
    do: "def main(xs) = mergesort(xs, fn(v) -> length(v) < #{t})"

  defp program(:wordcount, t),
    do: "def main(text) = word_count(text, fn(v) -> length(v) < #{t})"

  defp program(:cube, t) do
    source = File.read!(Path.join(to_string(:code.priv_dir(:thunk)), "demos/cube.thunk"))

    source <>
      "\ndef main(dims) = render(head(dims), head(tail(dims)), head(tail(tail(dims))), fn(rows) -> length(rows) < #{t})"
  end

  defp program(:mandelbrot, t) do
    source = File.read!(Path.join(to_string(:code.priv_dir(:thunk)), "demos/mandelbrot.thunk"))

    source <>
      "\ndef main(d) = render(head(d), head(tail(d)), head(tail(tail(d))), fn(rows) -> length(rows) < #{t})"
  end

  defp input(:mergesort, opts, seed, _frame, _frames) do
    :rand.seed(:exsss, {seed, seed, seed})
    for _ <- 1..(opts[:size] || 10_000), do: :rand.uniform(1_000_000)
  end

  defp input(:wordcount, opts, seed, _frame, _frames) do
    :rand.seed(:exsss, {seed, seed, seed})
    words = ~w(alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu)
    Enum.map_join(1..(opts[:size] || 10_000), " ", fn _ -> Enum.random(words) end)
  end

  defp input(:cube, opts, _seed, frame, frames) do
    [opts[:width] || 160, opts[:height] || 120, @first_angle + div(frame * @two_pi, frames)]
  end

  defp input(:mandelbrot, opts, _seed, _frame, _frames) do
    [opts[:width] || 160, opts[:height] || 120, opts[:iterations] || 200]
  end

  defp describe(:cube, [w, h, angle]), do: "#{w}x#{h} angle=#{angle}"
  defp describe(:mandelbrot, [w, h, max]), do: "#{w}x#{h} iterations=#{max}"
  defp describe(:mergesort, xs), do: "size=#{length(xs)}"
  defp describe(:wordcount, text), do: "size=#{length(String.split(text))}"

  defp check(:mergesort, input, result), do: result == Enum.sort(input)

  defp check(:wordcount, input, result) do
    Map.new(result, fn [w, n] -> {w, n} end) == Enum.frequencies(String.split(input))
  end

  defp check(demo, [w, h, _], rows) when demo in [:cube, :mandelbrot] do
    length(rows) == h and Enum.all?(rows, &(length(&1) == w)) and
      Enum.all?(List.flatten(rows), &(&1 in 0..255))
  end

  defp save_image(rows, path) do
    File.write!(path, Image.bmp(rows))
    Mix.shell().info("image written to #{path}")
    Enum.each(Image.ascii(rows, 80), fn line -> Mix.shell().info(line) end)
  end

  defp save_animation(frames, path) do
    File.write!(path, Image.gif(frames, 10))
    Mix.shell().info("animation of #{length(frames)} frames written to #{path}")
    Enum.each(Image.ascii(List.last(frames), 80), fn line -> Mix.shell().info(line) end)
  end
end
