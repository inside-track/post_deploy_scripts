defmodule PostDeployScripts.PreviouslyRunScripts do
  # Define a schema that works with the a table, which is schema_migrations by default
  @moduledoc false
  use Ecto.Schema

  import Ecto.Query, only: [from: 2]

  @primary_key false
  schema "previously_run_scripts" do
    field :version, :integer
    timestamps updated_at: false
  end

  @opts [timeout: :infinity, log: false]

  def ensure_previously_run_table!(repo, prefix) do
    adapter = repo.__adapter__
    create_previously_run_table(adapter, repo, prefix)
  end

  def versions(repo, prefix) do
    from(p in get_source(repo), select: type(p.version, :integer))
    |> Map.put(:prefix, prefix)
    |> repo.all(@opts)
  end

  def up(repo, version, prefix) do
    %__MODULE__{version: version}
    |> Ecto.put_meta(prefix: prefix, source: get_source(repo))
    |> repo.insert!(@opts)
  end

  def down(repo, version, prefix) do
    from(p in get_source(repo), where: p.version == type(^version, :integer))
    |> Map.put(:prefix, prefix)
    |> repo.delete_all(@opts)
  end

  def get_source(repo) do
    Keyword.get(repo.config, :scripts_source, "previously_run_scripts")
  end

  defp create_previously_run_table(adapter, repo, prefix) do
    table_name = repo |> get_source |> String.to_atom
    table = %Ecto.Migration.Table{name: table_name, prefix: prefix}

    # DDL queries do not log, so we do not need to pass log: false here.
    adapter.execute_ddl(repo,
      {:create_if_not_exists, table, [
        {:add, :version, :bigint, primary_key: true},
        {:add, :inserted_at, :naive_datetime, []}]}, @opts)
  end
end
