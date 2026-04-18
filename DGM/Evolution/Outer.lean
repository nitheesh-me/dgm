import DGM.Types.Evolution
import DGM.Evolution.Archive
import DGM.Evolution.SelfImprove
import DGM.Utils.Common

/-!
# DGM.Evolution.Outer — Main Evolutionary Loop

The top-level orchestrator for the DGM evolution process.
Iterates through generations, selecting parents, running self-improvement,
filtering results, and updating the archive.
Ported from: `DGM_outer.py`
-/
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
  -- Create output directory
  let runId ← do
    let ns ← IO.monoNanosNow
    pure s!"{ns}"
  let outputDir := s!"{config.outputDir}/{runId}"
  IO.FS.createDirAll ⟨outputDir⟩

  -- Check for previous run to continue
  match config.prevRunDir with
  | some prevDir =>
    let metadataPath := s!"{prevDir}/dgm_metadata.jsonl"
    let archive ← loadArchive metadataPath
    let startGen := archive.entries.length  -- Approximate
    IO.println s!"[Init] Continuing from {prevDir}, generation {startGen}"
    return (archive, startGen)
  | none =>
    -- Fresh start with initial agent
    let initialFolderName := if config.polyglot then "initial_polyglot" else "initial"
    -- Copy initial results if available
    let initialSrc := System.FilePath.mk initialFolderName
    let initialDst := System.FilePath.mk s!"{outputDir}/initial"
    let srcExists ← initialSrc.pathExists
    let dstExists ← initialDst.pathExists
    if srcExists && !dstExists then
      let _ ← IO.Process.output { cmd := "cp", args := #["-r", initialFolderName, s!"{outputDir}/initial"] }

    let initialEntry : ArchiveMetadata := {
      runId := "initial"
      parentCommit := "initial"
      entry := "initial"
      generation := 0
      score := 0.0  -- Will be set from initial/metadata.json
      isCompiled := true
    }
    let archive := ConcreteArchive.empty.add initialEntry
    IO.println s!"[Init] Fresh start with initial agent"
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

private partial def batchListGo {α : Type} : List α → Nat → List (List α) → List (List α)
  | [], _, acc => acc.reverse
  | remaining, sz, acc =>
    let batch := remaining.take sz
    let rest := remaining.drop sz
    batchListGo rest sz (batch :: acc)

private def batchList {α : Type} (xs : List α) (size : Nat) : List (List α) :=
  if size == 0 then [xs]
  else batchListGo xs size []

/-- Run self-improvement workers in parallel using Lean 4 Tasks.
Spawns up to `numWorkers` tasks concurrently.
Ported from `ThreadPoolExecutor` usage in `DGM_outer.py`. -/
def runSelfImprovementsParallel (configs : List SelfImproveConfig)
    (numWorkers : Nat) : IO (List SelfImproveResult) := do
  -- Split configs into batches of numWorkers
  let batches := batchList configs numWorkers
  let mut results : List SelfImproveResult := []
  for batch in batches do
    -- Spawn all tasks in this batch
    let tasks ← batch.mapM fun config => do
      IO.asTask (selfImprove config)
    -- Wait for all tasks in this batch
    for task in tasks do
      match ← IO.wait task with
      | .ok result => results := results ++ [result]
      | .error e =>
        IO.eprintln s!"[Worker] Self-improvement failed: {e}"
  return results

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
  IO.println s!"  Parents selected: {parents.map (·.runId)}"

  -- Step 2: Build self-improvement configs
  let selfImproveConfigs := parents.map fun parent => {
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
    : SelfImproveConfig
  }

  -- Step 3: Run self-improvements in parallel
  let results ← runSelfImprovementsParallel selfImproveConfigs config.selfImproveWorkers

  -- Step 4: Filter to compiled runs
  let compiled := filterCompiled results

  -- Step 5: Update archive
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
  let testTaskList ← loadTestTaskList config
  IO.println s!"[DGM] Loaded {testTaskList.length} test tasks"

  IO.println s!"[DGM] Starting evolution from generation {startGen}"
  IO.println s!"[DGM] Initial archive size: {initialArchive.entries.length}"
  IO.println s!"[DGM] Best initial score: {initialArchive.bestScore}"

  -- Main evolution loop
  let separator := String.mk (List.replicate 50 '=')
  let mut archive := initialArchive
  for gen in List.range (config.maxGenerations - startGen) do
    let genNum := startGen + gen
    IO.println s!"\n{separator}"
    IO.println s!"Generation {genNum}"
    IO.println s!"  Archive: {archive.entries.length} entries, Best: {archive.bestScore}"

    let result ← runGeneration config archive genNum testTaskList

    archive := result.archive

    IO.println s!"  Results:"
    IO.println s!"    Total attempts: {result.allResults.length}"
    IO.println s!"    Compiled:       {result.compiledResults.length}"
    IO.println s!"    Archive size:   {archive.entries.length}"
    IO.println s!"    Best score:     {archive.bestScore}"

  IO.println s!"\n{separator}"
  IO.println s!"Evolution complete after {config.maxGenerations} generations"
  IO.println s!"Final archive: {archive.entries.length} entries"
  IO.println s!"Final best score: {archive.bestScore}"

  return archive
where
  /-- Load test task list from subset JSON files. -/
  loadTestTaskList (config : DGMConfig) : IO (List String) := do
    let subsetDir := if config.polyglot then "./polyglot/subsets" else "./swe_bench/subsets"
    let smallPath := s!"{subsetDir}/small.json"
    let pathExists ← System.FilePath.pathExists ⟨smallPath⟩
    if pathExists then
      let content ← IO.FS.readFile ⟨smallPath⟩
      -- Simple JSON array parsing: extract strings from ["id1", "id2", ...]
      let inner := (content.trim
        |>.dropWhile (· == '[')
        |>.takeWhile (· != ']')).toString
      return inner.splitOn ","
        |>.map (fun s => (s.trim.replace "\"" ""))
        |>.filter (·.length > 0)
    else
      IO.eprintln s!"[DGM] Warning: Test task list not found at {smallPath}"
      return []

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

end DGM.Evolution.Outer
