# Thunk

A distributed evaluator for pure functional computations, built with Elixir on the BEAM.
Individual project for Distributed Systems / Distributed Software Systems, University of Bologna, Cesena.

## Status

Milestone 2: the language and interpreter from milestone 1, plus peer
nodes with decentralized work stealing and a Docker Compose demo cluster.
Every node is a peer; there is no coordinator. A piece of work whose
thief crashes or whose node disappears is solved again by its owner, so a
job survives losing nodes mid-run. Nodes can join a running cluster
knowing a single seed, and a web dashboard shows the nodes while jobs
run. Termination detection and memoization remain optional extensions.

## Approved scope

- Combinator API: map, reduce, and divide-and-conquer, represented as an operator DSL.
- Recursive task decomposition controlled by a size threshold.
- Peer workers, decentralized work stealing, and combination of partial results.
- Multi-node demonstration using Docker Compose.

## The language

Programs are S-expressions. The core has five special forms (`lambda`, `if`,
`let`, `def`, `dc`) and thirteen primitives (`add sub mul div mod lt eq cons
head tail nil? chars string`). Everything else, including `map`, `fold`,
`pmap`, `reduce` and `mergesort`, is defined in `priv/prelude.thunk` in the
language itself.

`dc` is the only parallel form:

```lisp
(def mergesort (lambda (xs small?)
  (dc xs small? halves insertion-sort merge-sorted)))
```

It takes a value, a predicate that says when a value is solved directly, a
function that splits it in two, the base case and the merge. Which process or
node solves each piece is up to the scheduler; the result is the same.

```elixir
ctx = Thunk.Prelude.load()
ctx = Thunk.load("(def main (lambda (xs) (mergesort xs (lambda (v) (lt (length v) 8)))))", ctx)
Thunk.run(ctx, [3, 1, 2])
Thunk.run(Thunk.with_scheduler(ctx, Thunk.Scheduler.Local), [3, 1, 2])
```

## Running on several nodes

Every node is a peer. It keeps a deque of pieces of work, evaluates pieces
itself up to a configurable limit, and when idle asks a random connected
node for its oldest piece. A job is submitted from any node; the program's
definitions travel with it, so only the prelude has to be on every node.

Configuration is by environment: `THUNK_PEERS` (comma-separated seed
nodes), `THUNK_LIMIT` (evaluators this node runs from its own deque,
default the number of schedulers).

Nodes can join and leave a running cluster. A node needs only one
reachable seed: it retries its seeds every second until it knows a
member, then finds the others by gossip. When a node connects to another,
and every two or three seconds, it asks a random connected node for its
member list and connects to the nodes it did not know. This does not
rely on the full mesh of the BEAM, so it also works with
`-connect_all false`. A node that disappears is dropped from the list,
and a restarted node comes back through its seeds. `Thunk.Cluster.members/1`
returns the nodes a given node knows. New nodes steal work at once, also
from a job that is already running.

Demo cluster with Docker Compose:

```text
docker compose up -d --build
docker compose exec node1 sh -c 'elixir --sname client --cookie thunk-demo -S mix thunk.demo mergesort --size 20000 --threshold 500'
docker compose --profile join up -d --scale joiner=2
docker compose exec node1 elixir --sname probe --cookie thunk-demo -e "IO.inspect(:erpc.call(:thunk@node1, Thunk.Cluster, :members, []))"
docker compose --profile join down
```

The `joiner` service only knows `thunk@node1`; its replicas are named
after their container id.

`mix thunk.demo` also takes `wordcount`, `--repeat`, `--seed`, `--limit`
and `--scheduler sequential|local|distributed`. A third demo, `cube`, is a
raytracer written in the language with fixed-point arithmetic
(`priv/demos/cube.thunk`): `mix thunk.demo cube --width 640 --height 480`
renders the image row by row across the cluster, writes `cube.bmp` and
prints a preview. `mandelbrot` (`priv/demos/mandelbrot.thunk`) renders the
Mandelbrot set the same way, with `--iterations` for the limit per pixel;
its rows cost very different amounts of work, which is where small pieces
and stealing matter most. Multi-node tests start peer
nodes on the same machine and need a working `epmd`; they are skipped with
a message if distribution cannot be started.

## Dashboard

`mix thunk.dashboard --port 4000` serves a web page at
`http://localhost:4000` that shows every node of the cluster while jobs
run: evaluators running out of the limit, deque length, steals, pieces
given away, evaluated and recovered, and a chart of pieces evaluated per
second over the last two minutes. It polls the workers every 500 ms; a
node that stops answering stays on the page as down. The dashboard is a
node of its own that joins the cluster and does not evaluate pieces. With
the Compose cluster running, in a second terminal:

```text
docker compose exec node1 sh -c 'elixir --sname dash --cookie thunk-demo -S mix thunk.dashboard --port 4000'
```

Port 4000 of `node1` is published by `compose.yaml`. The server is a few
lines of `:gen_tcp`, the page is plain HTML and JavaScript, and
`/stats.json` returns the same data the page draws.

## Development

Pinned versions: Elixir 1.20.4 on Erlang/OTP 29.1, image
`hexpm/elixir:1.20.4-erlang-29.1-debian-bookworm-20260918-slim`.
No third-party dependencies.

```text
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

On Windows PowerShell use `iex.bat -S mix` to start the shell (`iex` is a PowerShell alias).
