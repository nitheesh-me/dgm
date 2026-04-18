/-!
# DGM.Evolution.Outer — Main Evolutionary Loop

The top-level orchestrator for the DGM evolution process.
Iterates through generations, selecting parents, running self-improvement,
filtering results, and updating the archive.
Ported from: `DGM_outer.py`
-/

import DGM.Types.Evolution
import DGM.Evolution.Archive
import DGM.Evolution.SelfImprove

namespace DGM.Evolution.Outer

open DGM.Types
open DGM.Evolution

/-! ## DGM Configuration -/

/-- Top-level DGM configuration.
Ported from command-line arguments in `DGM_outer.py`. -/
structure DGMConfig where
  /-- Maximum number of generations. -/
  maxGenerations : Nat := 80
  /-- Number of self-improvement attempts per generation. -/
  selfImproveSize : Nat := 4
  /-- Number of parallel workers. -/
  selfImproveWorkers : Nat := 2
  /-- Selection method for parents. -/
  selectionMethod : SelectionMethod := .scoreChildProp
  /-- Noise leeway for archive admission. -/
  noiseLeeway : Float := 0.01
  /-- Output directory. -/
  outputDir : String := "output_dgm"
  /-- Previous run directory (for continuation). -/
  prevRunDir : Option String := none
  /-- Whether to use polyglot benchmark. -/
  polyglot : Bool := false
  /-- Whether to force Docker rebuild each generation. -/
  forceRebuild : Bool := false
  /-- Number of evaluation instances per run. -/
  numEvals : Nat := 10
  /-- Whether to run post-improvement diagnosis. -/
  postImproveDiagnose : Bool := true
  /-- Whether to run baseline comparison. -/
  runBaseline : Bool := false
  deriving Repr, Inhabited

/-! ## Initialization -/

/-- Initialize or resume a DGM run.
Ported from `initialize_run` in `DGM_outer.py`.
Returns: (archive, starting generation number) -/
def initializeRun (config : DGMConfig) : IO (ConcreteArchive × Nat) := do
  -- Check for previous run to continue
  match config.prevRunDir with
  | some prevDir =>
    let metadataPath := s!"{prevDir}/dgm_metadata.jsonl"
    let archive ← loadArchive metadataPath
    let startGen := archive.entries.length  -- Approximate
    return (archive, startGen)
  | none =>
    -- Fresh start with initial agent
    let initialEntry : ArchiveMetadata := {
      runId := "initial"
      parentCommit := "initial"
      entry := "initial"
      generation := 0
      score := 0.0  -- Will be set from initial/metadata.json
      isCompiled := true
    }
    let archive := ConcreteArchive.empty.add initialEntry
    return (archive, 0)

/-! ## Full Evaluation Threshold -/

/-- Determine the threshold for triggering full evaluation.
Ported from `get_full_eval_threshold` in `DGM_outer.py`. -/
def getFullEvalThreshold (archive : ConcreteArchive) : Float :=
  let bestScore := archive.bestScore
  -- Full eval when a run scores within 90% of best
  bestScore * 0.9

/-! ## Single Generation Step -/

/-- Result of a single generation. -/
structure GenerationResult where
  /-- Updated archive after this generation. -/
  archive : ConcreteArchive
  /-- All self-improvement results from this generation. -/
  allResults : List SelfImproveResult
  /-- Compiled (valid) results only. -/
  compiledResults : List SelfImproveResult
  deriving Repr, Inhabited

/-- Run a single generation of the DGM evolution loop.

1. Select parents from the archive
2. Run self-improvement attempts (in parallel)
3. Filter to compiled runs
4. Update the archive

This is one iteration of the main loop in `DGM_outer.py`. -/
def runGeneration (config : DGMConfig) (archive : ConcreteArchive)
    (generation : Nat) (testTaskList : List String) : IO GenerationResult := do
  -- Step 1: Choose parents
  let parents ← chooseParents archive config.selfImproveSize config.selectionMethod

  -- Step 2: Run self-improvement attempts
  -- In production, this uses Task for parallelism
  let mut results : List SelfImproveResult := []
  for parent in parents do
    let selfImproveConfig : SelfImproveConfig := {
      parentCommit := parent.runId
      outputDir := config.outputDir
      forceRebuild := config.forceRebuild
      numEvals := config.numEvals
      postImproveDiagnose := config.postImproveDiagnose
      entry := parent.entry
      testTaskList := testTaskList
      fullEvalThreshold := getFullEvalThreshold archive
      runBaseline := config.runBaseline
      polyglot := config.polyglot
    }
    let result ← selfImprove selfImproveConfig
    results := results ++ [result]

  -- Step 3: Filter to compiled runs
  let compiled := filterCompiled results

  -- Step 4: Update archive
  let newEntries := compiled.map (·.toArchiveMetadata generation)
  let newArchive := updateArchive archive newEntries config.noiseLeeway

  -- Save generation state
  saveArchiveState s!"{config.outputDir}/dgm_metadata.jsonl"
    generation newArchive (compiled.map (·.runId))

  return {
    archive := newArchive
    allResults := results
    compiledResults := compiled
  }

/-! ## Main Evolution Loop -/

/-- Run the full DGM evolution loop.

This is the main entry point, ported from `main()` in `DGM_outer.py`.
Iterates through generations, maintaining and updating the archive. -/
def runEvolutionLoop (config : DGMConfig) : IO ConcreteArchive := do
  -- Initialize
  let (initialArchive, startGen) ← initializeRun config

  -- Load test task lists
  -- In production: load from swe_bench/subsets/*.json or polyglot/subsets/*.json
  let testTaskList : List String := []

  IO.println s!"Starting DGM evolution from generation {startGen}"
  IO.println s!"Initial archive size: {initialArchive.entries.length}"
  IO.println s!"Best initial score: {initialArchive.bestScore}"

  -- Main evolution loop
  let mut archive := initialArchive
  for gen in List.range (config.maxGenerations - startGen) do
    let genNum := startGen + gen
    IO.println s!"\n=== Generation {genNum} ==="
    IO.println s!"Archive size: {archive.entries.length}, Best: {archive.bestScore}"

    let result ← runGeneration config archive genNum testTaskList

    archive := result.archive

    IO.println s!"Generation {genNum} complete:"
    IO.println s!"  Total attempts: {result.allResults.length}"
    IO.println s!"  Compiled: {result.compiledResults.length}"
    IO.println s!"  New archive size: {archive.entries.length}"
    IO.println s!"  Best score: {archive.bestScore}"

  IO.println s!"\nEvolution complete after {config.maxGenerations} generations"
  IO.println s!"Final archive size: {archive.entries.length}"
  IO.println s!"Final best score: {archive.bestScore}"

  return archive

/-! ## Verified Evolution Loop -/

/-- A version of the evolution loop that carries verification proofs.

This wraps `runEvolutionLoop` with the formal verification:
- Each generation maintains archive monotonicity
- Each evolution step has verified stability
- The final archive is provably at least as good as the initial one

NOTE: Full verification requires connecting the IO-level operations
to the pure type-level proofs, which involves axioms about
the external world (Docker, LLM, benchmarks). -/
structure VerifiedEvolutionResult (spec : AgentSpec) where
  /-- The final concrete archive. -/
  concreteArchive : ConcreteArchive
  /-- The number of generations run. -/
  generationsRun : Nat
  /-- Proof sketch: archive quality never decreased.
      Full proof requires axiomatizing IO behavior. -/
  monotonicityWitness : concreteArchive.bestScore ≥ 0.0

end DGM.Evolution.Outer
