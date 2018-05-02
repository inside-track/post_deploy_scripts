defmodule Mix.Tasks.Pds.Gen.Script do
  use Mix.Task

  import Macro, only: [camelize: 1, underscore: 1]
  import Mix.Generator

  import Mix.Ecto

  import PostDeployScripts 

  @shortdoc "Generates a new script"

  @moduledoc """
  Generates a post deploy script.

  The repository must be set under `:ecto_repos` in the
  current app configuration or given via the `-r` option.

  ## Examples

      mix pds.gen.script sync_users
      mix pds.gen.script sync_users -r Custom.Repo

  The generated script filename will be prefixed with the current
  timestamp in UTC which is used for versioning and ordering.

  By default, the migration will be generated to the
  "priv/post_deploy_scripts" directory of the current application.

  ## Command line options

    * `-r`, `--repo` - the repo to generate script for

  """

  @switches [change: :string]

  @doc false
  def run(args) do
    no_umbrella!("pds.gen.script")
    repos = parse_repo(args)

    Enum.each repos, fn repo ->
      case OptionParser.parse(args, switches: @switches) do
        {opts, [name], _} ->
          ensure_repo(repo, args)
          path = post_deploy_scripts_path(repo)
          base_name = "#{underscore(name)}.exs"
          file = Path.join(path, "#{timestamp()}_#{base_name}")
          create_directory path

          fuzzy_path = Path.join(path, "*_#{base_name}")
          if Path.wildcard(fuzzy_path) != [] do
            Mix.raise "script can't be created, there is already a post deploy script file with name #{name}."
          end

          assigns = [mod: Module.concat([PostDeployScripts, camelize(name)]), change: opts[:change]]
          create_file file, migration_template(assigns)

          if open?(file) and Mix.shell.yes?("Do you want to run this post deploy script?") do
            Mix.Task.run "pds.run", [repo]
          end
        {_, _, _} ->
          Mix.raise "expected pds.gen.script to receive the post deploy script file name, " <>
                    "got: #{inspect Enum.join(args, " ")}"
      end
    end
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: << ?0, ?0 + i >>
  defp pad(i), do: to_string(i)

  embed_template :migration, """
  defmodule <%= inspect @mod %> do
    use Ecto.Migration

    def up do

    end

    def down do
      
    end
  end
  """
end
