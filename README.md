# Thunk

A distributed evaluator for pure functional computations, built with Elixir on the BEAM.
Individual project for Distributed Systems / Distributed Software Systems, University of Bologna, Cesena.

## Status

Milestone 2: the language and interpreter from milestone 1, plus peer
nodes with decentralized work stealing and a Docker Compose demo cluster.
Every node is a peer; there is no coordinator. Worker failure recovery,
termination detection, memoization, dynamic membership and a dashboard
remain optional extensions.

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

Configuration is by environment: `THUNK_PEERS` (comma-separated node names
to connect to at boot), `THUNK_LIMIT` (evaluators this node runs from its
own deque, default the number of schedulers).

Demo cluster with Docker Compose:

```text
docker compose up -d --build
docker compose exec node1 sh -c 'elixir --sname client --cookie thunk-demo -S mix thunk.demo mergesort --size 20000 --threshold 500'
docker compose down
```

`mix thunk.demo` also takes `wordcount`, `--repeat`, `--seed`, `--limit`
and `--scheduler sequential|local|distributed`. Multi-node tests start peer
nodes on the same machine and need a working `epmd`; they are skipped with
a message if distribution cannot be started.

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
