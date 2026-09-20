FROM hexpm/elixir:1.20.4-erlang-29.1-debian-bookworm-20260918-slim

WORKDIR /app
ENV MIX_ENV=prod

COPY mix.exs .formatter.exs ./
COPY lib lib
COPY priv priv
RUN mix compile

# THUNK_NODE, THUNK_COOKIE and THUNK_PEERS come from compose.yaml. Short
# names: the node is THUNK_NODE@<container hostname>, resolved by Compose DNS.
# Without a hostname in compose.yaml the hostname is the short container id,
# which Docker also resolves, so scaled replicas get distinct node names.
CMD ["sh", "-c", "elixir --sname ${THUNK_NODE:-thunk} --cookie $THUNK_COOKIE -S mix run --no-halt"]
