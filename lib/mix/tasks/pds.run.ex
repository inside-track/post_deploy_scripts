defmodule Mix.Tasks.Pds.Run do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Runs the repository post deploy scripts"

  @moduledoc """
  Runs the pending post deploy scripts.

  ## Examples

      mix pds.run
      mix pds.run -r Custom.Repo

      mix pds.run -n 3
      mix pds.run --step 3

      mix pds.run -v 20080906120000
      mix pds.run --to 20080906120000

  ## Command line options

    * `-r`, `--repo` - the repo
    * `--all` - run all pending post deploy scripts
    * `--step` / `-n` - run n number of pending post deploy scripts
    * `--to` / `-v` - run all post deploy scripts up to and including version
    * `--quiet` - do not log post deploy script commands
    * `--prefix` - the prefix to run post deploy scripts on
    * `--pool-size` - the pool size if the repository is started only for the task (defaults to 1)
    * `--log-sql` - log the raw sql post deploy scripts are running

  """

  @doc false
  def run(args) do
    repos = parse_repo(args)

    {opts, _, _} = OptionParser.parse args,
      switches: [all: :boolean, step: :integer, to: :integer, quiet: :boolean,
                 prefix: :string, pool_size: :integer, log_sql: :boolean],
      aliases: [n: :step, v: :to]

    opts =
      if opts[:to] || opts[:step] || opts[:all],
        do: opts,
        else: Keyword.put(opts, :all, true)

    opts =
      if opts[:quiet],
        do: Keyword.merge(opts, [log: false, log_sql: false]),
        else: opts

    Enum.each repos, fn repo ->
      ensure_repo(repo, args)
      PostDeployScripts.ensure_scripts_path(repo)
      {:ok, pid, apps} = ensure_started(repo, opts)

      pool = repo.config[:pool]
      migrated =
        if function_exported?(pool, :unboxed_run, 2) do
          pool.unboxed_run(repo, fn -> PostDeployScripts.Migrator.run(repo, PostDeployScripts.post_deploy_scripts_path(repo), :up, opts) end)
        else
          PostDeployScripts.Migrator.run(repo, :up, opts)
        end

      pid && repo.stop(pid)
      restart_apps_if_migrated(apps, migrated)
    end
  end
end
