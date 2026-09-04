defmodule Thunk.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Thunk.TaskSupervisor},
      {Thunk.Worker, Application.get_env(:thunk, :worker, [])}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Thunk.Supervisor)
  end
end
