FROM hexpm/elixir:1.20.4-erlang-29.1-debian-bookworm-20260918-slim

WORKDIR /app
ENV MIX_ENV=prod

COPY mix.exs .formatter.exs ./
COPY lib lib
COPY priv priv
COPY src src
RUN mix compile

# Short node names use the container hostname (or id for scaled replicas).
CMD ["sh", "-c", "elixir --sname ${THUNK_NODE:-thunk} --cookie $THUNK_COOKIE -S mix run --no-halt"]
