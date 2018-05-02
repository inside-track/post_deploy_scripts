defmodule Mix.Tasks.Pds.Revert do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Revert post deploy scripts previously run"

  @moduledoc """
  Reverts applied post deploy scripts.

  Scripts are expected at "priv/YOUR_REPO/post_deploy_scripts" directory
  of the current application but it can be configured by specifying
  the `:priv` key under the repository configuration.

  Runs the latest applied script by default. To revert to
  a version number, supply `--to version_number`. To revert a
  specific number of times, use `--step n`. To undo all applied
  scripts, provide `--all`.

  ## Examples

      mix pds.revert
      mix pds.revert -r Custom.Repo

      mix pds.revert -n 3
      mix pds.revert --step 3

      mix pds.revert -v 20080906120000
      mix pds.revert --to 20080906120000

  ## Command line options

    * `--all` - revert all applied scripts
    * `--step` / `-n` - revert n number of applied scripts
    * `--to` / `-v` - revert all scripts down to and including version
    * `--quiet` - do not log script commands
    * `--prefix` - the prefix to run scripts on
    * `--pool-size` - the pool size if the repository is started only for the task (defaults to 1)
    * `--log-sql` - log the raw sql scripts are running

  """

  @doc false
  def run(args) do
    repos = parse_repo(args)

    {opts, _, _} = OptionParser.parse args,
      switches: [all: :boolean, step: :integer, to: :integer, start: :boolean,
                 quiet: :boolean, prefix: :string, pool_size: :integer, log_sql: :boolean],
      aliases: [n: :step, v: :to]

    opts =
      if opts[:to] || opts[:step] || opts[:all],
        do: opts,
        else: Keyword.put(opts, :step, 1)

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
          pool.unboxed_run(repo, fn -> PostDeployScripts.Migrator.run(repo, :down, opts) end)
        else
          PostDeployScripts.Migrator.run(repo, :down, opts)
        end

      pid && repo.stop(pid)
      restart_apps_if_migrated(apps, migrated)
    end
  end
end
