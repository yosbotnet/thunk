defmodule Thunk.Membership do
  @moduledoc """
  Keeps track of the other thunk nodes and connects to them.

  A node starts from a list of seeds (THUNK_PEERS) and needs only one of
  them to be reachable. While it knows no member it keeps trying the
  seeds, once a second. After that it learns the rest of the cluster by
  gossip: whenever a node comes up, and every few seconds with some
  jitter, it asks a random connected node for its member list and
  connects to the nodes it did not know. This works without the default
  full mesh of the BEAM, so also with `-connect_all false`.

  A member is a connected node that answered a gossip message, so nodes
  that do not run thunk (a shell, a client) are not listed. A node that
  goes down is just dropped; if it comes back it joins again through its
  seeds.

  Everything is a plain message. Node.connect can take seconds for an
  unreachable node, so it always runs in a separate process.
  """

  use GenServer
  require Logger

  @name __MODULE__

  defstruct seeds: [],
            members: MapSet.new(),
            interval: 2_000,
            seeding: nil,
            monitoring: false

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: @name)

  @doc "The thunk nodes known to `node`, itself included, sorted."
  @spec members(node) :: [node]
  def members(node \\ node()), do: GenServer.call({@name, node}, :members)

  @impl true
  def init(opts) do
    opts = Keyword.merge(env_opts(), opts)

    state = %__MODULE__{
      seeds: Keyword.get(opts, :seeds, []),
      interval: Keyword.get(opts, :interval, 2_000)
    }

    send(self(), :seed)
    {:ok, schedule_gossip(monitor(state))}
  end

  @impl true
  def handle_call(:members, _from, state) do
    {:reply, Enum.sort([node() | MapSet.to_list(state.members)]), state}
  end

  @impl true
  def handle_info({:pull, from}, state) do
    send(from, {:push, node(), MapSet.to_list(state.members)})
    {:noreply, add_member(state, node(from))}
  end

  def handle_info({:push, sender, nodes}, state) do
    state = add_member(state, sender)
    known = [node() | Node.list()]

    for n <- nodes, n not in known do
      spawn(Node, :connect, [n])
    end

    {:noreply, state}
  end

  def handle_info(:gossip, state) do
    state = monitor(state)

    case Node.list() do
      [] -> :ok
      nodes -> pull(Enum.random(nodes))
    end

    {:noreply, schedule_gossip(state)}
  end

  # Only one seed attempt at a time; Node.connect can take a while.
  def handle_info(:seed, %{seeding: nil} = state) do
    known = MapSet.new(Node.list())

    if state.seeds != [] and MapSet.size(state.members) == 0 do
      seeds = Enum.reject(state.seeds, &(&1 == node() or &1 in known))
      {pid, _mon} = spawn_monitor(fn -> Enum.each(seeds, &Node.connect/1) end)
      {:noreply, %{state | seeding: pid}}
    else
      {:noreply, state}
    end
  end

  def handle_info(:seed, state), do: {:noreply, state}

  def handle_info({:DOWN, _mon, :process, pid, _reason}, %{seeding: pid} = state) do
    Process.send_after(self(), :seed, 1_000)
    {:noreply, %{state | seeding: nil}}
  end

  def handle_info({:nodeup, n}, state) do
    pull(n)
    {:noreply, state}
  end

  def handle_info({:nodedown, n}, state) do
    if n in state.members do
      Logger.info("member left: #{n}")
      members = MapSet.delete(state.members, n)
      if MapSet.size(members) == 0, do: send(self(), :seed)
      {:noreply, %{state | members: members}}
    else
      {:noreply, state}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp pull(n), do: send({@name, n}, {:pull, self()})

  defp add_member(state, n) do
    cond do
      n == node() or n in state.members ->
        state

      n in Node.list() ->
        Logger.info("member joined: #{n}")
        %{state | members: MapSet.put(state.members, n)}

      true ->
        state
    end
  end

  # Tests may start distribution after the application.
  defp monitor(%{monitoring: false} = state) do
    if Node.alive?() do
      :net_kernel.monitor_nodes(true)
      %{state | monitoring: true}
    else
      state
    end
  end

  defp monitor(state), do: state

  defp schedule_gossip(state) do
    jitter = :rand.uniform(div(state.interval, 2) + 1)
    Process.send_after(self(), :gossip, state.interval + jitter)
    state
  end

  defp env_opts do
    case System.get_env("THUNK_PEERS") do
      nil ->
        []

      list ->
        seeds =
          list
          |> String.split(",", trim: true)
          |> Enum.map(&String.to_atom(String.trim(&1)))

        [seeds: seeds]
    end
  end
end
