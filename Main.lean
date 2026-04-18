import DGM

/-- Darwin Gödel Machine — Lean 4 entry point.
    Runs the outer evolutionary loop with verified self-improvement. -/
def main (args : List String) : IO Unit := do
  IO.println "Darwin Gödel Machine (Lean 4 — verified self-evolution)"
  IO.println s!"Arguments: {args}"
  -- TODO: parse CLI args and dispatch to DGM.Evolution.Outer.runEvolutionLoop
  let config : DGM.Evolution.Outer.DGMConfig := {
    maxGenerations := 80
    selfImproveSize := 4
    selfImproveWorkers := 2
    selectionMethod := .scoreChildProp
    noiseLeeway := 0.01
    polyglot := false
  }
  IO.println s!"Config: maxGen={config.maxGenerations}, workers={config.selfImproveWorkers}"
  IO.println "Use `lake build` to type-check all proofs."
  return ()
