# Thunk

A distributed evaluator for pure functional computations, built with Elixir on the BEAM.
Individual project for Distributed Systems / Distributed Software Systems, University of Bologna, Cesena.

## Status

Initial setup only: Mix project, empty OTP supervisor, formatter configuration, and Git defaults.
No evaluator, scheduler, network protocol, or demo is implemented yet.
The scaffold has not been compiled on the initial workstation: Elixir/Erlang are not currently available on PATH.

## Approved scope

- Combinator API: map, reduce, and divide-and-conquer, represented as an operator DSL.
- Recursive task decomposition controlled by a size threshold.
- Peer workers, decentralized work stealing, and combination of partial results.
- Multi-node demonstration using Docker Compose.

Worker failure recovery, Dijkstra-Scholten termination detection, memoization,
dynamic membership, and a dashboard are optional extensions.

## Development

Baseline: Elixir 1.18+ with a compatible Erlang/OTP release. Select and pin exact
versions when provisioning the development runtime. There are no third-party dependencies.

From this directory, once Elixir and Erlang are installed:

```text
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

The test harness is empty at this stage; it provides no functional coverage.
On Windows PowerShell use `iex.bat -S mix` to start the shell (`iex` is a PowerShell alias).

## Workspace material

The surrounding workspace keeps research, course requirements, example projects,
and reports in `../documentazione/`. Those files are intentionally outside this repository.
