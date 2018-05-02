defmodule PostDeployScriptsTest do
  use ExUnit.Case
  doctest PostDeployScripts

  test "greets the world" do
    assert PostDeployScripts.hello() == :world
  end
end
