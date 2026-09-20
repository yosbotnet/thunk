defmodule Thunk.Worker do
  @moduledoc """
  The peer process of a node. It holds the deque of pieces that may be
  stolen, the cache of job definitions, and the steal loop. It never
  evaluates anything itself: evaluators run under Thunk.TaskSupervisor.

  Own evaluators take the newest piece from the deque, thieves take the
  oldest. A worker steals only when its deque is empty and it has spare
  capacity, asking a random connected node and backing off when nobody
  has work.

  The worker never blocks on another node. Steal requests and replies
  are casts; the only remote call, fetching a job's definitions, is made
  by evaluator processes.
  """

  use GenServer
  require Logger

  alias Thunk.{Context, Piece, Prelude}
  alias Thunk.Scheduler.Distributed

  @name __MODULE__

  defstruct queue: :queue.new(),
            taken: %{},
            running: %{},
            limit: 0,
            prelude: nil,
            jobs: %{},
            steal: nil,
            timer: nil,
            backoff: 10,
            min_backoff: 10,
            max_backoff: 100,
            stats: %{steals: 0, stolen_from: 0, evaluated: 0, recovered: 0}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: @name)

  @doc "Offers a piece to thieves and to this node's own spare capacity."
  def push(%Piece{} = piece), do: GenServer.cast(@name, {:push, piece})

  @doc "Retrieves a pushed piece, or learns which worker took it."
  @spec take_back(reference) :: {:ok, Piece.t()} | {:stolen, pid} | {:error, :unknown}
  def take_back(ref), do: GenServer.call(@name, {:take_back, ref})

  def register_job(id, defs), do: GenServer.call(@name, {:register_job, id, defs})

  @doc "Asks the worker on `node` for the definitions of a job. Remote call."
  def fetch_job(node, id), do: GenServer.call({@name, node}, {:get_job, id}, 5_000)

  @doc "The context to evaluate a piece of `job` on this node, if known."
  @spec job_context(Context.job()) :: {:ok, Context.t()} | :unknown
  def job_context(job), do: GenServer.call(@name, {:job_context, job})

  @doc "Records that an evaluator on this node solved a lost piece again."
  def recovered, do: GenServer.cast(@name, :recovered)

  def prelude, do: GenServer.call(@name, :prelude)
  def set_limit(n) when is_integer(n) and n >= 0, do: GenServer.call(@name, {:set_limit, n})
  def stats(node \\ node(), timeout \\ 5_000), do: GenServer.call({@name, node}, :stats, timeout)

  @impl true
  def init(opts) do
    opts = Keyword.merge(env_opts(), opts)

    state = %__MODULE__{
      limit: Keyword.get(opts, :limit, System.schedulers_online()),
      min_backoff: Keyword.get(opts, :min_backoff, 10),
      max_backoff: Keyword.get(opts, :max_backoff, 100),
      prelude: Prelude.load()
    }

    state = %{state | backoff: state.min_backoff}
    if Node.alive?(), do: :net_kernel.monitor_nodes(true)
    {:ok, balance(state)}
  end

  @impl true
  def handle_call({:take_back, ref}, _from, state) do
    {matching, rest} = Enum.split_with(:queue.to_list(state.queue), &(&1.ref == ref))

    case matching do
      [piece] ->
        {:reply, {:ok, piece}, %{state | queue: :queue.from_list(rest)}}

      [] ->
        case Map.pop(state.taken, ref) do
          {nil, _} -> {:reply, {:error, :unknown}, state}
          {thief, taken} -> {:reply, {:stolen, thief}, %{state | taken: taken}}
        end
    end
  end

  def handle_call({:register_job, id, defs}, _from, state) do
    {:reply, :ok, %{state | jobs: Map.put(state.jobs, id, defs)}}
  end

  def handle_call({:get_job, id}, _from, state) do
    {:reply, Map.fetch(state.jobs, id), state}
  end

  def handle_call({:job_context, nil}, _from, state) do
    {:reply, {:ok, %{state.prelude | scheduler: Distributed, job: nil}}, state}
  end

  def handle_call({:job_context, {id, _origin} = job}, _from, state) do
    case state.jobs do
      %{^id => defs} ->
        {:reply, {:ok, %Context{defs: defs, scheduler: Distributed, job: job}}, state}

      _ ->
        {:reply, :unknown, state}
    end
  end

  def handle_call(:prelude, _from, state), do: {:reply, state.prelude, state}

  def handle_call({:set_limit, n}, _from, state) do
    {:reply, :ok, balance(%{state | limit: n})}
  end

  def handle_call(:stats, _from, state) do
    stats =
      Map.merge(state.stats, %{
        queued: :queue.len(state.queue),
        running: map_size(state.running),
        limit: state.limit,
        node: node()
      })

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:push, piece}, state) do
    {:noreply, balance(%{state | queue: :queue.in(piece, state.queue)})}
  end

  def handle_cast(:recovered, state) do
    {:noreply, %{state | stats: Map.update!(state.stats, :recovered, &(&1 + 1))}}
  end

  def handle_cast({:steal, thief}, state) do
    case :queue.out(state.queue) do
      {{:value, piece}, queue} ->
        send(thief, {:piece, piece})
        Logger.debug("gave piece #{inspect(piece.ref)} to #{inspect(node(thief))}")

        {:noreply,
         %{
           state
           | queue: queue,
             taken: Map.put(state.taken, piece.ref, thief),
             stats: Map.update!(state.stats, :stolen_from, &(&1 + 1))
         }}

      {:empty, _} ->
        send(thief, :none)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:piece, piece}, state) do
    Logger.debug("stole piece #{inspect(piece.ref)} from #{inspect(node(piece.reply_to))}")

    state = %{
      state
      | steal: nil,
        backoff: state.min_backoff,
        stats: Map.update!(state.stats, :steals, &(&1 + 1))
    }

    {:noreply, state |> start_evaluator(piece) |> balance()}
  end

  def handle_info(:none, state) do
    {:noreply, %{state | steal: nil, backoff: min(state.backoff * 2, state.max_backoff)}}
  end

  def handle_info(:tick, state) do
    state =
      case state.steal do
        nil ->
          %{state | timer: nil}

        _victim ->
          %{state | timer: nil, steal: nil, backoff: min(state.backoff * 2, state.max_backoff)}
      end

    {:noreply, balance(state)}
  end

  def handle_info({:DOWN, _mon, :process, pid, reason}, state) do
    case Map.pop(state.running, pid) do
      {nil, _} ->
        {:noreply, state}

      {{_mon, piece}, running} ->
        # The owner needs the reason to decide whether to retry.
        if reason != :normal, do: send(piece.reply_to, {:failed, piece.ref, reason})

        state = %{
          state
          | running: running,
            stats: Map.update!(state.stats, :evaluated, &(&1 + 1))
        }

        {:noreply, balance(state)}
    end
  end

  def handle_info({:nodeup, node}, state) do
    Logger.info("node up: #{node}")
    {:noreply, balance(state)}
  end

  def handle_info({:nodedown, node}, state) do
    Logger.info("node down: #{node}")
    steal = if state.steal == node, do: nil, else: state.steal
    {:noreply, %{state | steal: steal}}
  end

  # Try local work before asking another node.
  defp balance(state) do
    cond do
      map_size(state.running) >= state.limit ->
        state

      not :queue.is_empty(state.queue) ->
        {{:value, piece}, queue} = :queue.out_r(state.queue)

        %{state | queue: queue, taken: Map.put(state.taken, piece.ref, self())}
        |> start_evaluator(piece)
        |> balance()

      true ->
        maybe_steal(state)
    end
  end

  defp start_evaluator(state, %Piece{} = piece) do
    {:ok, pid} =
      Task.Supervisor.start_child(Thunk.TaskSupervisor, fn -> Distributed.run_piece(piece) end)

    send(piece.reply_to, {:claimed, piece.ref, pid})
    mon = Process.monitor(pid)
    %{state | running: Map.put(state.running, pid, {mon, piece})}
  end

  defp maybe_steal(%{steal: nil, timer: nil} = state) do
    case Node.list() do
      [] ->
        arm_timer(state)

      nodes ->
        victim = Enum.random(nodes)
        GenServer.cast({@name, victim}, {:steal, self()})
        arm_timer(%{state | steal: victim})
    end
  end

  defp maybe_steal(state), do: state

  defp arm_timer(state) do
    jitter = :rand.uniform(state.backoff)
    %{state | timer: Process.send_after(self(), :tick, state.backoff + jitter)}
  end

  defp env_opts do
    case System.get_env("THUNK_LIMIT") do
      nil -> []
      n -> [limit: String.to_integer(n)]
    end
  end
end
