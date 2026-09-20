defmodule Thunk.DashboardTest do
  use ExUnit.Case, async: false

  alias Thunk.Dashboard

  defp stats(evaluated, steals), do: %{evaluated: evaluated, steals: steals}

  # Plain http only, so :httpc is given its ssl options and does not
  # need :public_key to work out the defaults.
  defp get(url) do
    :httpc.request(:get, {String.to_charlist(url), []}, [ssl: []], body_format: :binary)
  end

  test "rates are the difference of two snapshots per second" do
    assert Dashboard.rates(stats(10, 2), stats(60, 7), 500) == %{evaluated: 100.0, steals: 10.0}
    assert Dashboard.rates(stats(0, 0), stats(3, 0), 2_000) == %{evaluated: 1.5, steals: 0.0}
  end

  test "a counter that went back to zero counts as no work, not negative work" do
    assert Dashboard.rates(stats(500, 40), stats(3, 1), 500) == %{evaluated: 0.0, steals: 0.0}
    assert Dashboard.rates(stats(1, 1), stats(2, 2), 0) == %{evaluated: 0.0, steals: 0.0}
  end

  test "collect skips a node that does not answer" do
    result = Dashboard.collect([node(), :"ghost@127.0.0.1"], 300)
    assert Map.keys(result) == [node()]
    assert %{node: node, limit: _, queued: _, evaluated: _} = result[node()]
    assert node == node()
  end

  test "a node that stops answering stays in the snapshot as down" do
    {:ok, nodes} = Agent.start_link(fn -> [node()] end)

    start_supervised!(
      {Dashboard, name: :dash_down, interval: 60_000, nodes: fn -> Agent.get(nodes, & &1) end}
    )

    snap = Dashboard.refresh(:dash_down)
    assert [%{name: name, up: true}] = snap.nodes
    assert name == node()

    Agent.update(nodes, fn _ -> [:"ghost@127.0.0.1"] end)
    snap = Dashboard.refresh(:dash_down)
    assert [%{name: ^name, up: false, eval_rate: +0.0}] = snap.nodes
    assert Map.has_key?(hd(snap.history).rates, name)
    assert List.last(snap.history).rates == %{}
  end

  @tag :distributed
  @tag :capture_log
  test "a peer node is shown up while it runs and down after it stops" do
    peer = Thunk.TestCluster.start_peer(:dash_peer)
    peer_node = Thunk.TestCluster.peer_node(peer)
    :ok = Thunk.Cluster.wait_for_peers(1, 10_000)
    start_supervised!({Dashboard, name: :dash_peer, interval: 60_000})

    snap = Dashboard.refresh(:dash_peer)
    assert %{up: true, limit: 2} = Enum.find(snap.nodes, &(&1.name == peer_node))

    Thunk.TestCluster.stop_peer(peer)
    snap = Dashboard.refresh(:dash_peer)
    assert %{up: false} = Enum.find(snap.nodes, &(&1.name == peer_node))
    assert %{up: true} = Enum.find(snap.nodes, &(&1.name == node()))
  end

  test "the page and the stats are served over HTTP" do
    {:ok, _} = Application.ensure_all_started(:inets)
    opts = [name: :dash_http, http_name: :dash_http_server, port: 0, ip: {127, 0, 0, 1}]
    start_supervised!({Dashboard, opts})
    start_supervised!({Dashboard.HTTP, opts})
    Dashboard.refresh(:dash_http)
    base = "http://127.0.0.1:#{Dashboard.HTTP.port(:dash_http_server)}"

    {:ok, {{_, 200, _}, headers, body}} = get(base <> "/")
    assert {~c"content-type", ~c"text/html; charset=utf-8"} in headers
    assert body =~ "<title>Thunk cluster</title>"

    {:ok, {{_, 200, _}, _, body}} = get(base <> "/stats.json")
    snap = JSON.decode!(body)
    assert snap["node"] == to_string(node())
    assert Enum.any?(snap["nodes"], &(&1["name"] == to_string(node()) and &1["up"]))
    assert is_list(snap["history"])

    assert {:ok, {{_, 404, _}, _, _}} = get(base <> "/nothing")
  end
end
