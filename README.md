# PostDeployScripts

**TODO: Add description**

PostDeployScripts is a Ecto Migration like language for writing project post deploy scripts.  It inherits Ecto Migration logic and options and provides the API to run, revert, and generate scripts

```bash
$ mix pds.gen.script test
==> post_deploy_scripts
Compiling 7 files (.ex)
Generated post_deploy_scripts app
==> itk
* creating priv/post_deploy_scripts
* creating priv/post_deploy_scripts/20180502150336_test.exs
$ mix pds.run
==> post_deploy_scripts
Compiling 1 file (.ex)
[info] == Running script PostDeployScripts.Test.up/0 forward
[info] == Executed in 0.0s
$ mix pds.run
[info] Already up
$ mix pds.revert
[info] == Running script PostDeployScripts.Test.down/0 forward
[info] == Executed in 0.0s
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `post_deploy_scripts` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:post_deploy_scripts, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/post_deploy_scripts](https://hexdocs.pm/post_deploy_scripts).

