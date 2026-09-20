defmodule Mix.Tasks.Thunk.Dashboard do
  @shortdoc "Serves a web page showing the cluster while jobs run"

  @moduledoc """
  Starts the dashboard: a web page with one card per node (evaluators
  running out of the limit, deque length, steals, pieces given away,
  evaluated and recovered) and a chart of pieces evaluated per second
  over the last two minutes. Nodes that stop answering stay on the page
  as down.

      mix thunk.dashboard --port 4000

  Run it as a node of the cluster, for example next to the Compose
  cluster:

      docker compose exec node1 sh -c 'elixir --sname dash --cookie thunk-demo -S mix thunk.dashboard --port 4000'

  and open http://localhost:4000. The node running the dashboard starts
  the thunk application like every other node, so it connects to the
  peers in THUNK_PEERS, but by default it does not evaluate pieces.

  Options: --port (default 4000), --ip (address to listen on, default
  0.0.0.0), --interval (ms between two collections, default 500),
  --connect (comma-separated nodes to connect to, besides THUNK_PEERS),
  --limit (evaluators this node may run itself, default 0).
  """

  use Mix.Task

  alias Thunk.{Cluster, Dashboard, Worker}

  @switches [port: :integer, ip: :string, interval: :integer, connect: :string, limit: :integer]

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: @switches)
    Mix.Task.run("app.start")

    Worker.set_limit(opts[:limit] || 0)

    if opts[:connect] do
      nodes = opts[:connect] |> String.split(",", trim: true) |> Enum.map(&String.to_atom/1)
      Mix.shell().info("connected to #{inspect(Cluster.connect(nodes))}")
    end

    unless Node.alive?() do
      Mix.shell().info("not a distributed node (no --sname or --name): showing this node only")
    end

    ip =
      case :inet.parse_address(String.to_charlist(opts[:ip] || "0.0.0.0")) do
        {:ok, ip} -> ip
        {:error, _} -> Mix.raise("invalid --ip #{opts[:ip]}")
      end

    port = opts[:port] || 4000

    case Dashboard.start(port: port, ip: ip, interval: opts[:interval] || 500) do
      {:ok, _} -> :ok
      {:error, reason} -> Mix.raise("cannot start the dashboard: #{inspect(reason)}")
    end

    Mix.shell().info("dashboard on http://localhost:#{Dashboard.HTTP.port()} (node #{node()})")
    Process.sleep(:infinity)
  end
end
