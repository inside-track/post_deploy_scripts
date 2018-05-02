defmodule PostDeployScripts.Migrator do
  @moduledoc """
  This module provides the post deploy script API.

  """

  require Logger

  alias Ecto.Migration.Runner
  alias PostDeployScripts.PreviouslyRunScripts

  import PostDeployScripts

  @doc """
  Gets all previously run versions.

  This function ensures the post deploy scripts table exists
  if no table has been defined yet.

  ## Options

    * `:log` - the level to use for logging. Defaults to `:info`.
      Can be any of `Logger.level/0` values or `false`.
    * `:prefix` - the prefix to run the post deploy scripts on

  """
  @spec previously_run_versions(Ecto.Repo.t, Keyword.t) :: [integer]
  def previously_run_versions(repo, opts \\ []) do
    verbose_schema_migration "previously run versions", fn ->
      PreviouslyRunScripts.ensure_previously_run_table!(repo, opts[:prefix])
      PreviouslyRunScripts.versions(repo, opts[:prefix])
    end
  end

  @doc """
  Runs a script on the given repository.

  ## Options

    * `:log` - the level to use for logging. Defaults to `:info`.
      Can be any of `Logger.level/0` values or `false`.
    * `:prefix` - the prefix to run the scripts on
  """
  @spec up(Ecto.Repo.t, integer, module, Keyword.t) :: :ok | :already_up | no_return
  def up(repo, version, module, opts \\ []) do
    versions = previously_run_versions(repo, opts)

    if version in versions do
      :already_up
    else
      do_up(repo, version, module, opts)
    end
  end

  defp do_up(repo, version, module, opts) do
    run_maybe_in_transaction repo, module, fn ->
      attempt(repo, module, :forward, :up, :up, opts)
        || attempt(repo, module, :forward, :change, :up, opts)
        || raise PostDeployScripts.RunError, "#{inspect module} does not implement a `up/0` or `change/0` function"
      verbose_schema_migration "update post deploy scripts tracking table", fn ->
        PreviouslyRunScripts.up(repo, version, opts[:prefix])
      end
    end
  end

  @doc """
  Runs a down post deploy script on the given repository.

  ## Options

    * `:log` - the level to use for logging. Defaults to `:info`.
      Can be any of `Logger.level/0` values or `false`.
    * `:prefix` - the prefix to run the post deploy scripts on

  """
  @spec down(Ecto.Repo.t, integer, module) :: :ok | :already_down | no_return
  def down(repo, version, module, opts \\ []) do
    versions = previously_run_versions(repo, opts)

    if version in versions do
      do_down(repo, version, module, opts)
    else
      :already_down
    end
  end

  defp do_down(repo, version, module, opts) do
    run_maybe_in_transaction repo, module, fn ->
      attempt(repo, module, :forward, :down, :down, opts)
        || attempt(repo, module, :backward, :change, :down, opts)
        || raise PostDeployScripts.RunError, "#{inspect module} does not implement a `down/0` or `change/0` function"
      verbose_schema_migration "update post deploy scripts tracking table", fn ->
        PreviouslyRunScripts.down(repo, version, opts[:prefix])
      end
    end
  end

  defp run_maybe_in_transaction(repo, module, fun) do
    cond do
      module.__migration__[:disable_ddl_transaction] ->
        fun.()
      repo.__adapter__.supports_ddl_transaction? ->
        repo.transaction(fun, [log: false, timeout: :infinity])
      true ->
        fun.()
    end
  end

  defp attempt(repo, module, direction, operation, reference, opts) do
    if Code.ensure_loaded?(module) and
       function_exported?(module, operation, 0) do
        run_script(repo, module, direction, operation, reference, opts)
      :ok
    end
  end

  defp run_script(repo, module, direction, operation, reference, opts) do
    level = Keyword.get(opts, :log, :info)
    sql = Keyword.get(opts, :log_sql, false)
    log = %{level: level, sql: sql}
    args  = [self(), repo, direction, reference, log]

    {:ok, runner} = Supervisor.start_child(Ecto.Migration.Supervisor, args)
    Runner.metadata(runner, opts)

    log(level, "== Running script #{inspect(module)}.#{operation}/0 #{direction}")
    {time1, _} = :timer.tc(module, operation, [])
    {time2, _} = :timer.tc(&Runner.flush/0, [])
    time = time1 + time2
    log(level, "== Executed in #{inspect(div(time, 100_000) / 10)}s")

    Runner.stop()
  end

  @doc """
  Runs post deploy scripts for the given repository.

  Equivalent to:

      PostDeployScripts.Migrator.run(repo, PostDeployScripts.Migrator.post_deploy_scripts_path(repo), direction, opts)

  """
  @spec run(Ecto.Repo.t, atom, Keyword.t) :: [integer]
  def run(repo, direction, opts) do
    run(repo, post_deploy_scripts_path(repo), direction, opts)
  end

  @doc """
  Apply post deploy scripts to a repository with a given strategy.

  The second argument identifies where the post deploy scripts are sourced from. A file
  path may be passed, in which case the post deploy scripts will be loaded from this
  during the post deploy script process. The other option is to pass a list of tuples
  that identify the version number and post deploy script modules to be run, for example:

      PostDeployScripts.Migrator.run(Repo, [{0, MyApp.Migration1}, {1, MyApp.Migration2}, ...], :up, opts)

  A strategy must be given as an option.

  ## Options

    * `:all` - runs all available if `true`
    * `:step` - runs the specific number of post deploy scripts
    * `:to` - runs all until the supplied version is reached
    * `:log` - the level to use for logging. Defaults to `:info`.
      Can be any of `Logger.level/0` values or `false`.
    * `:prefix` - the prefix to run the post deploy scripts on

  """
  @spec run(Ecto.Repo.t, binary | [{integer, module}], atom, Keyword.t) :: [integer]
  def run(repo, migration_source, direction, opts) do
    versions = previously_run_versions(repo, opts)

    cond do
      opts[:all] ->
        run_all(repo, versions, migration_source, direction, opts)
      to = opts[:to] ->
        run_to(repo, versions, migration_source, direction, to, opts)
      step = opts[:step] ->
        run_step(repo, versions, migration_source, direction, step, opts)
      true ->
        raise ArgumentError, "expected one of :all, :to, or :step strategies"
    end
  end

  @doc """
  Returns an array of tuples as the post deploy script status of the given repo,
  without actually running any post deploy scripts.

  Equivalent to:

      PostDeployScripts.Migrator.scripts(repo, PostDeployScripts.Migrator.post_deploy_scripts_path(repo))

  """
  @spec scripts(Ecto.Repo.t) :: [{:up | :down, id :: integer(), name :: String.t}]
  def scripts(repo) do
    PostDeployScripts.Migrator.scripts(repo, PostDeployScripts.post_deploy_scripts_path(repo))
  end

  @doc """
  Returns an array of tuples as the post deploy script status of the given repo,
  without actually running any post deploy scripts.
  """
  @spec scripts(Ecto.Repo.t, String.t) :: [{:up | :down, id :: integer(), name :: String.t}]
  def scripts(repo, directory) do
    repo
    |> previously_run_versions()
    |> collect_migrations(directory)
    |> Enum.sort_by(fn {_, version, _} -> version end)
  end

  defp run_to(repo, versions, migration_source, direction, target, opts) do
    within_target_version? = fn
      {version, _, _}, target, :up ->
        version <= target
      {version, _, _}, target, :down ->
        version >= target
    end

    pending_in_direction(versions, migration_source, direction)
    |> Enum.take_while(&(within_target_version?.(&1, target, direction)))
    |> migrate(direction, repo, opts)
  end

  defp run_step(repo, versions, migration_source, direction, count, opts) do
    pending_in_direction(versions, migration_source, direction)
    |> Enum.take(count)
    |> migrate(direction, repo, opts)
  end

  defp run_all(repo, versions, migration_source, direction, opts) do
    pending_in_direction(versions, migration_source, direction)
    |> migrate(direction, repo, opts)
  end

  defp pending_in_direction(versions, migration_source, :up) do
    migrations_for(migration_source)
    |> Enum.filter(fn {version, _name, _file} -> not (version in versions) end)
  end

  defp pending_in_direction(versions, migration_source, :down) do
    migrations_for(migration_source)
    |> Enum.filter(fn {version, _name, _file} -> version in versions end)
    |> Enum.reverse
  end

  defp collect_migrations(versions, migration_source) do
    ups_with_file =
      versions
      |> pending_in_direction(migration_source, :down)
      |> Enum.map(fn {version, name, _} -> {:up, version, name} end)

    ups_without_file =
      versions
      |> versions_without_file(migration_source)
      |> Enum.map(fn version -> {:up, version, "** FILE NOT FOUND **"} end)

    downs =
      versions
      |> pending_in_direction(migration_source, :up)
      |> Enum.map(fn {version, name, _} -> {:down, version, name} end)

    ups_with_file ++ ups_without_file ++ downs
  end

  defp versions_without_file(versions, migration_source) do
    versions_with_file =
      migration_source
      |> migrations_for
      |> Enum.map(&elem(&1, 0))

    versions -- versions_with_file
  end

  # This function will match directories passed into `Migrator.run`.
  defp migrations_for(migration_source) when is_binary(migration_source) do
    query = Path.join(migration_source, "*")

    for entry <- Path.wildcard(query),
        info = extract_migration_info(entry),
        do: info
  end

  # This function will match specific version/modules passed into `Migrator.run`.
  defp migrations_for(migration_source) when is_list(migration_source) do
    Enum.map migration_source, fn({version, module}) -> {version, module, :existing_module} end
  end

  defp extract_migration_info(file) do
    base = Path.basename(file)
    ext  = Path.extname(base)

    case Integer.parse(Path.rootname(base)) do
      {integer, "_" <> name} when ext == ".exs" ->
        {integer, name, file}
      _ ->
        nil
    end
  end

  defp migrate([], direction, _repo, opts) do
    level = Keyword.get(opts, :log, :info)
    log(level, "Already #{direction}")
    []
  end

  defp migrate(migrations, direction, repo, opts) do
    ensure_no_duplication(migrations)

    Enum.map migrations, fn {version, name_or_mod, file} ->
      mod = extract_module(file, name_or_mod)
      case direction do
        :up   -> do_up(repo, version, mod, opts)
        :down -> do_down(repo, version, mod, opts)
      end
      version
    end
  end

  defp ensure_no_duplication([{version, name, _} | t]) do
    if List.keyfind(t, version, 0) do
      raise Ecto.MigrationError,
            "scripts can't be executed, version #{version} is duplicated"
    end

    if List.keyfind(t, name, 1) do
      raise Ecto.MigrationError,
            "scripts can't be executed, name #{name} is duplicated"
    end

    ensure_no_duplication(t)
  end

  defp ensure_no_duplication([]), do: :ok

  defp is_migration_module?({mod, _bin}), do: function_exported?(mod, :__migration__, 0)
  defp is_migration_module?(mod), do: function_exported?(mod, :__migration__, 0)

  defp extract_module(:existing_module, mod) do
    if is_migration_module?(mod), do: mod, else: raise_no_migration_in_module(mod)
  end
  defp extract_module(file, _name) do
    modules = Code.load_file(file)
    case Enum.find(modules, &is_migration_module?/1) do
      {mod, _bin} -> mod
      _otherwise -> raise_no_migration_in_file(file)
    end
  end

  defp verbose_schema_migration(reason, fun) do
    try do
      fun.()
    rescue
      error ->
        Logger.error """
        Could not #{reason}. This error usually happens due to the following:

          * The database does not exist
          * The "post_deploy_scripts" table, which PostDeplyScripts uses for managing
            script versions, was defined by another library

        To fix the first issue, run "mix ecto.create".

        To address the second, you can run "mix ecto.drop" followed by
        "mix ecto.create".
        """
        reraise error, System.stacktrace
    end
  end

  defp raise_no_migration_in_file(file) do
    raise Ecto.MigrationError,
          "file #{Path.relative_to_cwd(file)} is not post deploy script"
  end
  defp raise_no_migration_in_module(mod) do
    raise Ecto.MigrationError,
          "module #{inspect mod} is not post deploy script"
  end

  defp log(false, _msg), do: :ok
  defp log(level, msg),  do: Logger.log(level, msg)
end
