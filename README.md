# Thunk

A distributed evaluator for pure functional computations, built with Elixir on the BEAM.
Individual project for Distributed Systems / Distributed Software Systems, University of Bologna, Cesena.

## Status

Milestone 1: the language, the interpreter, a sequential scheduler and a
process-based local scheduler, with a prelude written in the language and
two demos (mergesort and word count). No networking yet.

## Approved scope

- Combinator API: map, reduce, and divide-and-conquer, represented as an operator DSL.
- Recursive task decomposition controlled by a size threshold.
- Peer workers, decentralized work stealing, and combination of partial results.
- Multi-node demonstration using Docker Compose.

Worker failure recovery, Dijkstra-Scholten termination detection, memoization,
dynamic membership, and a dashboard are optional extensions.

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

## Development

Pinned versions: Elixir 1.20.4 on Erlang/OTP 29.1. No third-party dependencies.

```text
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

On Windows PowerShell use `iex.bat -S mix` to start the shell (`iex` is a PowerShell alias).
