defmodule Thunk.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Thunk.TaskSupervisor},
      {Thunk.Worker, Application.get_env(:thunk, :worker, [])},
      {Thunk.Membership, Application.get_env(:thunk, :membership, [])}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Thunk.Supervisor)
  end
end
