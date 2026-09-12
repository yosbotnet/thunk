distributed? =
  try do
    Thunk.TestCluster.ensure_distributed!()
    true
  rescue
    e ->
      IO.puts("distributed tests skipped: #{Exception.message(e)}")
      false
  end

ExUnit.start(exclude: if(distributed?, do: [], else: [:distributed]))
