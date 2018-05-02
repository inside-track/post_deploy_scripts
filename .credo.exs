%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/"],
        excluded: []
      },
      checks: [
        {Credo.Check.Refactor.FunctionArity, max_arity: 6},
        {Credo.Check.Readability.MaxLineLength, max_length: 120},
        {Credo.Check.Design.AliasUsage, false}
      ]
    }
  ]
}
