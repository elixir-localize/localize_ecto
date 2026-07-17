# Credo configuration for Localize Ecto.
#
# Policy decisions follow the localize project (July 2026):
#
# * `Design.AliasUsage` is disabled. The localize family deliberately
#   fully qualifies many calls because module names such as
#   `Localize.List`, `Localize.Date` and `Localize.String` shadow the
#   standard library when aliased. The preferred style is to alias
#   submodules opportunistically when the trailing segment does NOT
#   clash with the stdlib, and never as a bulk conversion.
#
# * `Refactor.Nesting` stays at the default maximum depth of 2:
#   multi-clause helper functions with pattern matching are preferred
#   over nested case/cond/if.
#
# * `Refactor.CyclomaticComplexity` stays at the default of 9;
#   naturally-branchy functions carry inline `credo:disable`
#   annotations with a one-line justification instead of a raised
#   global limit.
%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: ["lib/", "test/"],
        excluded: []
      },
      checks: %{
        disabled: [
          {Credo.Check.Design.AliasUsage, []}
        ]
      }
    }
  ]
}
