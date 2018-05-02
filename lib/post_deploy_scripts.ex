defmodule PostDeployScripts do
  @moduledoc """
  Generate, run and revert post deploy scripts
  """


  @doc """
  Ensures the post deploy scripts path exists on the file system.
  """
  @spec ensure_scripts_path(Ecto.Repo.t) :: Ecto.Repo.t | no_return
  def ensure_scripts_path(repo) do
    with false <- Mix.Project.umbrella?,
         path = post_deploy_scripts_path(repo),
         false <- File.dir?(path),
         do: raise_missing_scripts(Path.relative_to_cwd(path))
    repo
  end


  @doc """
  Gets the post deploy scripts path.
  """
  def post_deploy_scripts_path(repo) do
    Path.join(source_priv(repo), "post_deploy_scripts")
  end

  defp source_priv(repo) do
    config = repo.config()
    priv = config[:priv] || "priv"
    app = Keyword.fetch!(config, :otp_app)
    Path.join(Mix.Project.deps_paths[app] || File.cwd!, priv)
  end

  defp raise_missing_scripts(path) do
    Mix.raise """
    Could not find post deploy scripts directory #{inspect path}.

    This may be because you are in a new project and the
    post deploy scripts directory has not been created yet. 
    Creating an empty directory at the path above will fix 
    this error.

    If you expected existing scripts to be found, please
    make sure your repository has been properly configured
    and the configured path exists.
    """
  end
end
