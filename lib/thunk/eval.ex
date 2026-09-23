defmodule Thunk.Eval do
  @moduledoc """
  Tree-walking interpreter for the language.

  A form is the data produced by Thunk.Parser. The environment is a map
  from symbol to value, the context carries the definitions table and
  the scheduler. Symbols are resolved in the environment, then in the
  definitions, then among the primitives.

  Special forms: lambda (written fn in the source), if, let, def (top
  level only, handled by Thunk.load) and dc. Any other list is an
  application.

  The branches of if, the body of let, the body of a closure and the
  application itself are in tail position, so loops written as recursive
  functions in the language run in constant stack.
  """

  import Kernel, except: [apply: 3]

  alias Thunk.{Context, Error, Primitives, Work}

  @type value :: term

  @spec eval(term, map, Context.t()) :: value
  def eval(n, _env, _ctx) when is_integer(n), do: n
  def eval(b, _env, _ctx) when is_boolean(b), do: b
  def eval(s, _env, _ctx) when is_binary(s), do: s
  def eval([], _env, _ctx), do: []

  def eval(name, env, ctx) when is_atom(name) do
    case env do
      %{^name => value} -> value
      _ -> lookup_def(name, ctx)
    end
  end

  def eval([:lambda, params, body], env, _ctx) when is_list(params) do
    if Enum.all?(params, &is_atom/1) do
      {:closure, params, body, env}
    else
      raise Error, "malformed lambda: parameters must be symbols"
    end
  end

  def eval([:lambda | _], _env, _ctx), do: raise(Error, "malformed lambda")

  def eval([:if, cond, then, else_], env, ctx) do
    case eval(cond, env, ctx) do
      true -> eval(then, env, ctx)
      false -> eval(else_, env, ctx)
      other -> raise Error, "if condition is not a boolean: #{inspect(other)}"
    end
  end

  def eval([:if | _], _env, _ctx), do: raise(Error, "malformed if")

  def eval([:let, name, value, body], env, ctx) when is_atom(name) do
    eval(body, Map.put(env, name, eval(value, env, ctx)), ctx)
  end

  def eval([:let | _], _env, _ctx), do: raise(Error, "malformed let")

  def eval([:def | _], _env, _ctx), do: raise(Error, "def is only allowed at top level")

  def eval([:dc, value, pred, split, base, merge], env, ctx) do
    [value, pred, split, base, merge] =
      Enum.map([value, pred, split, base, merge], &eval(&1, env, ctx))

    work = %Work{value: value, pred: pred, split: split, base: base, merge: merge}
    ctx.scheduler.solve(work, ctx)
  end

  def eval([:dc | _], _env, _ctx), do: raise(Error, "malformed dc")

  def eval([f | args], env, ctx) do
    callable = eval(f, env, ctx)
    values = eval_args(args, env, ctx)
    apply(callable, values, ctx)
  end

  def eval(other, _env, _ctx), do: raise(Error, "cannot evaluate #{inspect(other)}")

  @doc """
  Calls a closure or a primitive with already evaluated arguments.
  """
  @spec apply(value, [value], Context.t()) :: value
  def apply({:closure, params, body, env}, args, ctx) do
    case bind(env, params, args) do
      :arity -> raise Error, "expected #{length(params)} argument(s), got #{length(args)}"
      env -> eval(body, env, ctx)
    end
  end

  def apply({:primitive, name}, args, _ctx), do: Primitives.call(name, args)
  def apply(other, _args, _ctx), do: raise(Error, "not a function: #{inspect(other)}")

  # Most calls have at most three arguments. Avoid Enum.map on this path.
  defp eval_args([], _env, _ctx), do: []
  defp eval_args([a], env, ctx), do: [eval(a, env, ctx)]

  defp eval_args([a, b], env, ctx) do
    x = eval(a, env, ctx)
    [x, eval(b, env, ctx)]
  end

  defp eval_args([a, b, c], env, ctx) do
    x = eval(a, env, ctx)
    y = eval(b, env, ctx)
    [x, y, eval(c, env, ctx)]
  end

  defp eval_args([a | rest], env, ctx) do
    x = eval(a, env, ctx)
    [x | eval_args(rest, env, ctx)]
  end

  defp lookup_def(name, %Context{defs: defs}) do
    case defs do
      %{^name => value} ->
        value

      _ ->
        case Primitives.lookup(name) do
          {:ok, primitive} -> primitive
          :error -> raise Error, "unbound symbol #{name}"
        end
    end
  end

  # Bind parameters and arguments together; a length mismatch returns :arity.
  defp bind(env, [p | params], [a | args]), do: bind(Map.put(env, p, a), params, args)
  defp bind(env, [], []), do: env
  defp bind(_env, _params, _args), do: :arity
end
