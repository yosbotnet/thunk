defmodule Thunk.Dashboard do
  @moduledoc """
  Collects the counters of every worker in the cluster for the web
  dashboard.

  Every interval (500 ms by default) it asks the worker of this node and
  of every connected node for its stats. The calls run in parallel with
  a timeout, so a node that stopped answering is skipped instead of
  holding up the others. Counters are cumulative, so the rates (pieces
  evaluated and steals per second) come from the difference between two
  consecutive answers of the same node.

  A node that answered once and then disappears stays in the snapshot,
  marked as down with its last known counters, so a killed node is
  still visible on the page. The snapshot keeps a short history (the
  last two minutes at the default interval) of the evaluation rate of
  every node.

  The HTTP side is Thunk.Dashboard.HTTP below; start/1 starts both.
  """

  use GenServer

  alias Thunk.Worker

  @history 240
  @counters [:steals, :stolen_from, :evaluated, :recovered, :queued, :running, :limit]

  # Client API

  @doc """
  Starts the collector and the HTTP server under one supervisor.
  Options: :port (default 4000, 0 for any free port), :ip (default
  {0, 0, 0, 0}), :interval in ms (default 500).
  """
  def start(opts \\ []) do
    children = [
      {__MODULE__, opts},
      {Thunk.Dashboard.HTTP, opts}
    ]

    Supervisor.start_link(children, strategy: :rest_for_one)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "The latest snapshot: one entry per known node plus the rate history."
  def snapshot(server \\ __MODULE__), do: GenServer.call(server, :snapshot)

  @doc "Collects once, right now, without waiting for the next interval."
  def refresh(server \\ __MODULE__), do: GenServer.call(server, :refresh)

  @doc """
  Asks every node in `nodes` for its worker stats, in parallel, waiting
  at most `timeout` ms. Nodes that fail or do not answer in time are
  left out of the result.
  """
  @spec collect([node], non_neg_integer) :: %{node => map}
  def collect(nodes, timeout) do
    nodes
    |> Enum.uniq()
    |> Task.async_stream(fn node -> {node, fetch(node, timeout)} end,
      timeout: timeout + 100,
      on_timeout: :kill_task,
      max_concurrency: max(length(nodes), 1)
    )
    |> Enum.reduce(%{}, fn
      {:ok, {node, {:ok, stats}}}, acc -> Map.put(acc, node, stats)
      _, acc -> acc
    end)
  end

  defp fetch(node, timeout) do
    {:ok, Worker.stats(node, timeout)}
  catch
    :exit, _ -> :error
  end

  @doc """
  Pieces evaluated and steals per second between two stats of the same
  node taken `ms` milliseconds apart. A counter that went down means
  the node was restarted; that interval counts as zero.
  """
  @spec rates(map, map, number) :: %{evaluated: float, steals: float}
  def rates(prev, curr, ms) when ms > 0 do
    %{
      evaluated: per_second(prev.evaluated, curr.evaluated, ms),
      steals: per_second(prev.steals, curr.steals, ms)
    }
  end

  def rates(_prev, _curr, _ms), do: %{evaluated: 0.0, steals: 0.0}

  defp per_second(before, now, ms), do: Float.round(max(now - before, 0) * 1000 / ms, 1)

  # Server

  @impl true
  def init(opts) do
    state = %{
      interval: Keyword.get(opts, :interval, 500),
      timeout: Keyword.get(opts, :timeout, 400),
      nodes: Keyword.get(opts, :nodes, fn -> [node() | Node.list()] end),
      started: now(),
      known: %{},
      history: []
    }

    send(self(), :tick)
    {:ok, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, snapshot_of(state), state}

  def handle_call(:refresh, _from, state) do
    state = update(state)
    {:reply, snapshot_of(state), state}
  end

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, state.interval)
    {:noreply, update(state)}
  end

  defp update(state) do
    at = now()
    fresh = collect(state.nodes.(), state.timeout)

    known =
      Map.new(Enum.uniq(Map.keys(state.known) ++ Map.keys(fresh)), fn node ->
        {node, entry(Map.get(state.known, node), Map.get(fresh, node), at)}
      end)

    rates = for {node, %{up: true} = e} <- known, into: %{}, do: {node, e.eval_rate}
    sample = %{t: at - state.started, rates: rates}
    %{state | known: known, history: Enum.take([sample | state.history], @history)}
  end

  # A node seen for the first time: no rate yet.
  defp entry(nil, stats, at), do: up_entry(stats, %{evaluated: 0.0, steals: 0.0}, at)

  # A node that did not answer this time: keep its last counters.
  defp entry(old, nil, _at), do: %{old | up: false, eval_rate: 0.0, steal_rate: 0.0}

  defp entry(%{up: false}, stats, at), do: entry(nil, stats, at)
  defp entry(old, stats, at), do: up_entry(stats, rates(old, stats, at - old.at), at)

  defp up_entry(stats, rates, at) do
    stats
    |> Map.take(@counters)
    |> Map.merge(%{up: true, at: at, eval_rate: rates.evaluated, steal_rate: rates.steals})
  end

  defp snapshot_of(state) do
    nodes =
      state.known
      |> Enum.sort_by(fn {node, _} -> node end)
      |> Enum.map(fn {node, e} -> e |> Map.delete(:at) |> Map.put(:name, node) end)

    %{
      node: node(),
      interval: state.interval,
      time: now() - state.started,
      nodes: nodes,
      history: Enum.reverse(state.history)
    }
  end

  defp now, do: System.monotonic_time(:millisecond)
end

defmodule Thunk.Dashboard.HTTP do
  @moduledoc """
  A very small HTTP/1.1 server on :gen_tcp for the dashboard. It knows
  two paths: GET / returns the page and GET /stats.json the collector's
  snapshot as JSON. Every connection is served by its own process and
  closed after one response.
  """

  use GenServer

  alias Thunk.Dashboard

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :http_name, __MODULE__))
  end

  @doc "The port the server listens on (useful when started with port 0)."
  def port(server \\ __MODULE__), do: GenServer.call(server, :port)

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 4000)
    ip = Keyword.get(opts, :ip, {0, 0, 0, 0})
    dashboard = Keyword.get(opts, :name, Dashboard)

    socket_opts = [:binary, packet: :http_bin, active: false, reuseaddr: true, ip: ip]

    case :gen_tcp.listen(port, socket_opts) do
      {:ok, listen} ->
        {:ok, port} = :inet.port(listen)
        spawn_link(fn -> accept(listen, dashboard) end)
        {:ok, %{listen: listen, port: port}}

      {:error, reason} ->
        {:stop, {:listen, port, reason}}
    end
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  defp accept(listen, dashboard) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        {:ok, pid} =
          Task.start(fn ->
            receive do
              :go -> serve(socket, dashboard)
            end
          end)

        :ok = :gen_tcp.controlling_process(socket, pid)
        send(pid, :go)
        accept(listen, dashboard)

      {:error, :closed} ->
        :ok
    end
  end

  defp serve(socket, dashboard) do
    with {:ok, {:http_request, method, {:abs_path, path}, _}} <- :gen_tcp.recv(socket, 0, 5_000),
         :ok <- skip_headers(socket) do
      [path | _] = String.split(path, "?", parts: 2)
      :gen_tcp.send(socket, respond(method, path, dashboard))
    end

    :gen_tcp.close(socket)
  end

  defp skip_headers(socket) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, :http_eoh} -> :ok
      {:ok, {:http_header, _, _, _, _}} -> skip_headers(socket)
      other -> other
    end
  end

  defp respond(:GET, "/", _dashboard) do
    reply(200, "text/html; charset=utf-8", Thunk.Dashboard.Page.html())
  end

  defp respond(:GET, "/stats.json", dashboard) do
    reply(200, "application/json", JSON.encode!(Dashboard.snapshot(dashboard)))
  catch
    :exit, _ -> reply(503, "text/plain", "collector not running\n")
  end

  defp respond(:GET, _path, _dashboard), do: reply(404, "text/plain", "not found\n")
  defp respond(_method, _path, _dashboard), do: reply(405, "text/plain", "only GET\n")

  defp reply(status, type, body) do
    reason =
      %{200 => "OK", 404 => "Not Found", 405 => "Method Not Allowed", 503 => "Unavailable"}

    [
      "HTTP/1.1 #{status} #{reason[status]}\r\n",
      "content-type: #{type}\r\n",
      "content-length: #{byte_size(body)}\r\n",
      "cache-control: no-store\r\n",
      "connection: close\r\n\r\n",
      body
    ]
  end
end
