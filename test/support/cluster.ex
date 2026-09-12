defmodule Thunk.TestCluster do
  @moduledoc """
  Helpers for multi-node tests: turns the test node into a distributed
  node and starts peer nodes with OTP's :peer module, each running the
  thunk application configured to connect back to the test node.
  """

  @cookie :thunk_test

  def ensure_distributed! do
    unless Node.alive?() do
      start_epmd()

      case Node.start(:"primary@127.0.0.1", name_domain: :longnames) do
        {:ok, _} -> Node.set_cookie(@cookie)
        {:error, reason} -> raise "cannot start distribution: #{inspect(reason)}"
      end
    end

    :ok
  end

  defp start_epmd do
    epmd =
      Path.join([
        to_string(:code.root_dir()),
        "erts-#{:erlang.system_info(:version)}",
        "bin",
        "epmd"
      ])

    System.cmd(epmd, ["-daemon"])
    Process.sleep(200)
  rescue
    _ -> :ok
  end

  def start_peer(name, opts \\ []) do
    paths = Enum.map(:code.get_path(), &to_charlist/1)

    # The control channel is a TCP socket (connection: 0 picks a free
    # port) rather than distribution, which on Windows drops the peer
    # link right after start. The app itself still talks over distribution.
    # Not linked: peers are stopped explicitly by the tests, possibly
    # from a different process than the one that started them.
    {:ok, pid, _node} =
      :peer.start(%{
        name: name,
        host: ~c"127.0.0.1",
        longnames: true,
        connection: 0,
        args: [~c"-setcookie", Atom.to_charlist(@cookie), ~c"-pa" | paths]
      })

    worker_opts =
      Keyword.merge([peers: [node()], limit: 2, min_backoff: 5, max_backoff: 20], opts)

    :ok = :peer.call(pid, Application, :put_env, [:thunk, :worker, worker_opts])
    {:ok, _} = :peer.call(pid, Application, :ensure_all_started, [:thunk])
    pid
  end

  def stop_peer(pid), do: :peer.stop(pid)

  def peer_node(pid), do: :peer.call(pid, Kernel, :node, [])
end
