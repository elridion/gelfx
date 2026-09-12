%{
  configs: [
    %{
      name: "default",
      # Keep all of Credo's default checks enabled, disabling only the ones
      # listed below. TODO tags are used here as deliberate notes for deferred
      # work (e.g. commented-out future tests) rather than as lint violations.
      checks: %{
        disabled: [
          {Credo.Check.Design.TagTODO, []}
        ]
      }
    }
  ]
}
