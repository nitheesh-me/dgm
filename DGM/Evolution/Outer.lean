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
  selfImproveSize : Nat := 2
  /-- Number of parallel workers. -/
  selfImproveWorkers : Nat := 2
  /-- Selection method for parents. -/
  selectionMethod : SelectionMethod := .scoreChildProp
  /-- Noise leeway for archive admission. -/
  noiseLeeway : Float := 0.1
  /-- Output directory. -/
  outputDir : String := "output_dgm"
  /-- Previous run directory (for continuation). -/
  prevRunDir : Option String := none
  /-- Whether to use polyglot benchmark. -/
  polyglot : Bool := false
  /-- Whether to force Docker rebuild each generation. -/
  forceRebuild : Bool := false
  /-- Number of evaluation instances per run. -/
  numEvals : Nat := 1
  /-- Whether to run post-improvement diagnosis. -/
  postImproveDiagnose : Bool := false
  /-- Baseline to run: none | "no_selfimprove" | "no_darwin". -/
  runBaseline : Option String := none
  /-- Run only shallow (small) evaluation, skip medium/full eval. -/
  shallowEval : Bool := false
  /-- Disable full evaluation even for top-performing runs. -/
  noFullEval : Bool := false
  /-- Archive update method: "keep_all" | "keep_better". -/
  updateArchive : String := "keep_all"
  deriving Repr, Inhabited

/-! ## Metadata Reading Helpers -/

/-- Read `accuracy_score` from a run's `metadata.json`.
Returns 0.0 if file not found or parsing fails. -/
def readMetadataScore (outputDir runId : String) : IO Float := do
  let path := s!"{outputDir}/{runId}/metadata.json"
  let pathExists ← System.FilePath.pathExists ⟨path⟩
  if !pathExists then return 0.0
  let content ← IO.FS.readFile ⟨path⟩
  match content.splitOn "\"accuracy_score\":" with
  | [_, rest] =>
    let numStr := (rest.trimAscii.takeWhile (fun c => c.isDigit || c == '.' || c == '-')).toString
    match numStr.splitOn "." with
    | [intPart, fracPart] =>
      let intVal := intPart.toNat?.getD 0
      let fracVal := fracPart.toNat?.getD 0
      let fracDivisor := Float.ofNat (10 ^ fracPart.length)
      return Float.ofNat intVal + Float.ofNat fracVal / fracDivisor
    | [intPart] => return Float.ofNat (intPart.toNat?.getD 0)
    | _ => return 0.0
  | _ => return 0.0

/-- Extract a JSON string-array field from a JSON content string. -/
def extractJsonStringArray (json field : String) : List String :=
  match json.splitOn s!"\"{field}\": [" with
  | [_, rest] =>
    match rest.splitOn "]" with
    | arrayContent :: _ =>
      arrayContent.splitOn ","
        |>.map (·.trimAscii.toString.replace "\"" "")
        |>.filter (·.length > 0)
    | _ => []
  | _ => []

/-- Performance info loaded from a run's metadata.json on disk. -/
structure RunPerformanceInfo where
  accuracyScore  : Float
  unresolvedIds  : List String
  resolvedIds    : List String
  emptyPatchIds  : List String
  childrenCount  : Nat := 0

/-- Read performance info from a run's metadata.json. -/
def readRunPerformanceInfo (outputDir runId : String) : IO (Option RunPerformanceInfo) := do
  let path := s!"{outputDir}/{runId}/metadata.json"
  let pathExists ← System.FilePath.pathExists ⟨path⟩
  if !pathExists then return none
  let content ← IO.FS.readFile ⟨path⟩
  let score ← readMetadataScore outputDir runId
  let unresolved := extractJsonStringArray content "total_unresolved_ids"
  let resolved   := extractJsonStringArray content "total_resolved_ids"
  let empty      := extractJsonStringArray content "total_emptypatch_ids"
  return some {
    accuracyScore := score
    unresolvedIds := unresolved
    resolvedIds   := resolved
    emptyPatchIds := empty
  }

/-- Get the starting generation number from a JSONL metadata file (last line). -/
def getStartGeneration (metadataPath : String) : IO Nat := do
  let pathExists ← System.FilePath.pathExists ⟨metadataPath⟩
  if !pathExists then return 0
  let content ← IO.FS.readFile ⟨metadataPath⟩
  let lines := content.splitOn "\n" |>.filter (·.length > 0)
  match lines.getLast? with
  | none => return 0
  | some lastLine =>
    match lastLine.splitOn "\"generation\":" with
    | [_, rest] =>
      let numStr := (rest.trimAscii.takeWhile Char.isDigit).toString
      return numStr.toNat?.getD 0 + 1
    | _ => return 0

/-! ## Full Evaluation Threshold -/

/-- Sentinel value: disables the full-evaluation gate. -/
def fullEvalDisabled : Float := 1000000.0

/-- Count total SWE-bench issues across small/medium/big subset files. -/
def countFullEvalIssues : IO Nat := do
  let mut total := 0
  for size in (["small", "medium", "big"] : List String) do
    let path := s!"./swe_bench/subsets/{size}.json"
    let pathExists ← System.FilePath.pathExists ⟨path⟩
    if pathExists then
      let content ← IO.FS.readFile ⟨path⟩
      -- Count quoted strings containing a '-' (these are issue IDs)
      let count := content.splitOn "\"" |>.filter (fun s => s.contains '-') |>.length
      total := total + count
  return if total == 0 then 100 else total

/-- Get the original (initial) agent's accuracy score from disk.
Ported from `get_original_score` in `DGM_outer.py`. -/
def getOriginalScore (outputDir : String) : IO Float :=
  readMetadataScore outputDir "initial"

/-- Determine the threshold for triggering full evaluation.
Ported from `get_full_eval_threshold` in `DGM_outer.py`.
Returns the second-highest fully-evaluated score (minimum 0.4). -/
def getFullEvalThreshold (outputDir : String) (archive : ConcreteArchive) : IO Float := do
  let numFullEval ← countFullEvalIssues
  let mut archiveScores : List Float := []
  for entry in archive.entries do
    let path := s!"{outputDir}/{entry.runId}/metadata.json"
    let pathExists ← System.FilePath.pathExists ⟨path⟩
    if !pathExists then continue
    let content ← IO.FS.readFile ⟨path⟩
    let submittedStr := match content.splitOn "\"total_submitted_instances\":" with
      | [_, rest] => (rest.trimAscii.takeWhile Char.isDigit).toString
      | _ => "0"
    let submitted := submittedStr.toNat?.getD 0
    if submitted >= numFullEval * 9 / 10 then
      let score ← readMetadataScore outputDir entry.runId
      archiveScores := archiveScores ++ [score]
  let initialScore ← readMetadataScore outputDir "initial"
  archiveScores := archiveScores ++ [initialScore]
  let sorted := archiveScores.mergeSort (· > ·)
  let threshold := match sorted with
    | _ :: s :: _ => s
    | s :: _      => s
    | _           => 0.4
  return max threshold 0.4

/-! ## Context Length Detection -/

/-- Check if any issue IDs have a repeated context-length error in their md logs.
Ported from `any_exceeding_context_length` in `DGM_outer.py`. -/
def anyExceedingContextLength (outputDir commitId : String)
    (instanceIds : List String) : IO Bool := do
  let errorStr := "Error in get_response_withtools: Error code: 400 - {'message': 'Input is too long for requested model.'}"
  let doubled := s!"{errorStr}\n{errorStr}"
  for instanceId in instanceIds do
    let logPath := s!"{outputDir}/{commitId}/logs/{instanceId}.md"
    let pathExists ← System.FilePath.pathExists ⟨logPath⟩
    if pathExists then
      let content ← IO.FS.readFile ⟨logPath⟩
      if content.containsSubstr doubled then
        return true
  return false

/-! ## Parent & Entry Selection -/

/-- Pick one item from a list using a pre-generated random float in [0,1). -/
def listPickRandom {α : Type} (items : List α) (r : Float) (fallback : α) : α :=
  if items.isEmpty then fallback
  else
    let idx := (r * Float.ofNat items.length).toUInt64.toNat % items.length
    -- Walk the list to index idx
    let rec go : List α → Nat → α
      | [], _       => fallback
      | x :: _, 0   => x
      | _ :: xs, n  => go xs (n - 1)
    go items idx

/-- Select k parent commits from candidates using the given selection method.
Ported from the parent-selection part of `choose_selfimproves`. -/
def selectParents (withChildren : List (String × RunPerformanceInfo)) (k : Nat)
    (method : SelectionMethod) : IO (List String) := do
  if withChildren.isEmpty then return []
  let sig (score : Float) : Float := 1.0 / (1.0 + Float.exp (-(10.0 * (score - 0.5))))
  match method with
  | .random =>
    let items := withChildren.map fun (c, _) => (c, 1.0)
    weightedRandomChoices items k
  | .best =>
    let sorted := withChildren.mergeSort (fun (_, a) (_, b) => a.accuracyScore > b.accuracyScore)
    let top := sorted.map (·.1) |>.take k
    if top.length >= k then return top.take k
    let items := top.map fun c => (c, 1.0)
    let extras ← weightedRandomChoices items (k - top.length)
    return top ++ extras
  | .scoreProp =>
    let items := withChildren.map fun (c, i) => (c, sig i.accuracyScore)
    weightedRandomChoices items k
  | .scoreChildProp =>
    let items := withChildren.map fun (c, i) =>
      (c, sig i.accuracyScore * (1.0 / (Float.ofNat i.childrenCount + 1.0)))
    weightedRandomChoices items k

/-- Pick a specific SWE-bench entry for a parent commit.
Uses special entry types (solve_empty_patches, solve_stochasticity, solve_contextlength)
with 25% probability each; otherwise picks a random unresolved ID.
Ported from entry-selection logic in `choose_selfimproves`. -/
def pickSelfImproveEntry (outputDir parentCommit : String) (info : RunPerformanceInfo)
    (polyglot : Bool) : IO String := do
  let emptyIds      := info.emptyPatchIds
  let resolvedIds   := info.resolvedIds
  let unresolvedIds := info.unresolvedIds
  let numTotal      := emptyIds.length + resolvedIds.length + unresolvedIds.length
  if polyglot then
    let pool := let pool0 := emptyIds ++ unresolvedIds
                if pool0.isEmpty then resolvedIds ++ emptyIds ++ unresolvedIds else pool0
    if pool.isEmpty then return "solve_all"
    let r ← randomFloat
    return listPickRandom pool r "solve_all"
  else
    -- 1. Solve empty patches (if >= 10% of tasks have empty patches)
    let r1 ← randomFloat
    if emptyIds.length >= numTotal / 10 && r1 < 0.25 then
      return "solve_empty_patches"
    -- 2. Solve stochasticity
    let r2 ← randomFloat
    if r2 < 0.25 then
      return "solve_stochasticity"
    -- 3. Solve context length
    let r3 ← randomFloat
    let hasContextIssue ← anyExceedingContextLength outputDir parentCommit (emptyIds ++ unresolvedIds)
    if hasContextIssue && r3 < 0.25 then
      return "solve_contextlength"
    -- 4. Pick a random unresolved entry
    if unresolvedIds.isEmpty then return "solve_stochasticity"
    let r4 ← randomFloat
    return listPickRandom unresolvedIds r4 "solve_all"

/-- Choose self-improvement entries for the current generation.
Ported from `choose_selfimproves` in `DGM_outer.py`.

Reads metadata.json from disk for each archive entry to get current
scores and ID lists, then selects (parentCommit, entry) pairs. -/
def chooseSelfImproves (outputDir : String) (archive : ConcreteArchive)
    (selfimproveSize : Nat) (method : SelectionMethod)
    (runBaseline : Option String := none) (polyglot : Bool := false)
    : IO (List (String × String)) := do
  -- Load candidate info from disk
  let mut withChildren : List (String × RunPerformanceInfo) := []
  for archEntry in archive.entries do
    match ← readRunPerformanceInfo outputDir archEntry.runId with
    | none =>
      IO.eprintln s!"[Choose] {archEntry.runId} not eligible (no metadata)"
    | some info =>
      -- Use in-memory childrenCount from archive entry
      let infoFull := { info with childrenCount := archEntry.childrenCount }
      withChildren := withChildren ++ [(archEntry.runId, infoFull)]
  if withChildren.isEmpty then return []

  -- Apply selection method to pick parent commits
  let parentCommits ← match runBaseline with
    | some "no_darwin" =>
      match withChildren.getLast? with
      | some (commit, _) => pure (List.replicate selfimproveSize commit)
      | none => pure []
    | _ =>
      selectParents withChildren selfimproveSize method

  -- For each selected parent, pick an entry
  let mut result : List (String × String) := []
  for parentCommit in parentCommits do
    match withChildren.find? (·.1 == parentCommit) with
    | none => continue
    | some (_, info) =>
      let entry ← pickSelfImproveEntry outputDir parentCommit info polyglot
      result := result ++ [(parentCommit, entry)]
  return result

/-! ## Archive Update (with original score comparison) -/

/-- Update the archive with new run results.
Ported from `update_archive` in `DGM_outer.py`.

- `keep_all`: admit any run that passes noise-leeway threshold vs worst score
- `keep_better`: admit only runs at or above (initialScore - noiseLeeway) -/
def updateArchiveFull (outputDir : String) (archive : ConcreteArchive)
    (newEntries : List ArchiveMetadata) (noiseLeeway : Float := 0.1)
    (method : String := "keep_all") : IO ConcreteArchive := do
  let qualified ← match method with
    | "keep_better" =>
      let originalScore ← getOriginalScore outputDir
      let threshold := originalScore - noiseLeeway
      pure (newEntries.filter fun e => e.score >= threshold)
    | _ =>
      pure (newEntries.filter fun e =>
        qualifiesForAdmission archive e.score noiseLeeway)
  let combined := archive.entries ++ qualified
  let sorted := combined.mergeSort (fun a b => a.score > b.score)
  return { entries := sorted }

/-! ## Initialization -/

/-- Initialize or resume a DGM run.
Ported from `initialize_run` in `DGM_outer.py`.
Returns: (archive, starting generation number) -/
def initializeRun (config : DGMConfig) : IO (ConcreteArchive × Nat) := do
  IO.FS.createDirAll ⟨config.outputDir⟩
  match config.prevRunDir with
  | some prevDir =>
    let metadataPath := s!"{prevDir}/dgm_metadata.jsonl"
    let archive  ← loadArchive metadataPath
    let startGen ← getStartGeneration metadataPath
    IO.println s!"[Init] Continuing from {prevDir}, generation {startGen}"
    return (archive, startGen)
  | none =>
    let initialFolderName := if config.polyglot then "initial_polyglot" else "initial"
    let initialDst := System.FilePath.mk s!"{config.outputDir}/initial"
    let srcExists ← (System.FilePath.mk initialFolderName).pathExists
    let dstExists ← initialDst.pathExists
    if srcExists && !dstExists then
      let _ ← IO.Process.output {
        cmd := "cp", args := #["-r", initialFolderName, s!"{config.outputDir}/initial"]
      }
    let initialScore ← readMetadataScore config.outputDir "initial"
    let archive := ConcreteArchive.empty.add {
      runId := "initial", parentCommit := "initial", entry := "initial",
      generation := 0, score := initialScore, isCompiled := true
    }
    IO.println "[Init] Fresh start with initial agent"
    return (archive, 0)

/-! ## Single Generation Step -/

/-- Result of a single generation. -/
structure GenerationResult where
  archive            : ConcreteArchive
  allResults         : List SelfImproveResult
  compiledResults    : List SelfImproveResult
  selfimproveEntries : List (String × String)
  deriving Repr, Inhabited

private partial def batchListGo {α : Type} : List α → Nat → List (List α) → List (List α)
  | [], _, acc => acc.reverse
  | remaining, sz, acc =>
    batchListGo (remaining.drop sz) sz (remaining.take sz :: acc)

private def batchList {α : Type} (xs : List α) (size : Nat) : List (List α) :=
  if size == 0 then [xs] else batchListGo xs size []

/-- Load a subset JSON file and return the list of issue IDs. -/
def loadSubset (polyglot : Bool) (name : String) : IO (List String) := do
  let subsetDir := if polyglot then "./polyglot/subsets" else "./swe_bench/subsets"
  let path := s!"{subsetDir}/{name}.json"
  let pathExists ← System.FilePath.pathExists ⟨path⟩
  if !pathExists then
    IO.eprintln s!"[DGM] Warning: subset not found at {path}"
    return []
  let content ← IO.FS.readFile ⟨path⟩
  let inner := (content.trimAscii
    |>.dropWhile (· == '[')
    |>.takeWhile (· != ']')).toString
  return inner.splitOn ","
    |>.map (fun s => (s.trimAscii.toString.replace "\"" ""))
    |>.filter (·.length > 0)

/-- Run self-improvement workers in parallel using Lean 4 Tasks. -/
def runSelfImprovementsParallel (configs : List SelfImproveConfig)
    (numWorkers : Nat) : IO (List SelfImproveResult) := do
  let batches := batchList configs numWorkers
  let mut results : List SelfImproveResult := []
  for batch in batches do
    let tasks ← batch.mapM fun config => IO.asTask (selfImprove config)
    for task in tasks do
      match ← IO.wait task with
      | .ok result => results := results ++ [result]
      | .error e   => IO.eprintln s!"[Worker] Self-improvement failed: {e}"
  return results

/-- Run a single generation of the DGM evolution loop.

1. Choose (parent, entry) pairs via `chooseSelfImproves`
2. Run self-improvement attempts in parallel
3. Filter to compiled runs
4. Update archive
5. Persist state to JSONL -/
def runGeneration (config : DGMConfig) (archive : ConcreteArchive)
    (generation : Nat) (testTaskList testTaskListMore : List String)
    : IO GenerationResult := do
  -- Step 1: Choose (parent, entry) pairs
  if config.runBaseline == some "no_selfimprove" then
    IO.println "  [Baseline] no_selfimprove: skipping self-improvement"
    return { archive := archive, allResults := [], compiledResults := [],
             selfimproveEntries := [] }

  let selfimproveEntries ← chooseSelfImproves
    config.outputDir archive config.selfImproveSize
    config.selectionMethod config.runBaseline config.polyglot
  IO.println s!"  Entries chosen: {selfimproveEntries.map (·.1)}"

  -- Step 2: Build self-improvement configs
  let fullThreshold ← if config.noFullEval then pure fullEvalDisabled
    else getFullEvalThreshold config.outputDir archive
  let siConfigs := selfimproveEntries.map fun (parentCommit, entry) => ({
    parentCommit     := parentCommit
    outputDir        := config.outputDir
    forceRebuild     := config.forceRebuild
    numEvals         := config.numEvals
    postImproveDiagnose := config.postImproveDiagnose
    entry            := entry
    testTaskList     := testTaskList
    testTaskListMore := testTaskListMore
    testMoreThreshold := 0.4
    fullEvalThreshold := fullThreshold
    runBaseline      := config.runBaseline
    shallowEval      := config.shallowEval
    polyglot         := config.polyglot
  } : SelfImproveConfig)

  -- Step 3: Run in parallel
  let results  ← runSelfImprovementsParallel siConfigs config.selfImproveWorkers

  -- Step 4: Filter compiled
  let compiled := filterCompiled results

  -- Step 5: Update archive
  let newEntries := compiled.map (·.toArchiveMetadata generation)
  let newArchive ← updateArchiveFull config.outputDir archive newEntries
    config.noiseLeeway config.updateArchive

  -- Persist to JSONL
  saveArchiveState s!"{config.outputDir}/dgm_metadata.jsonl"
    generation newArchive selfimproveEntries
    (results.map (·.runId)) (compiled.map (·.runId))

  return {
    archive            := newArchive
    allResults         := results
    compiledResults    := compiled
    selfimproveEntries := selfimproveEntries
  }

/-! ## Main Evolution Loop -/

/-- Run the full DGM evolution loop.
Ported from `main()` in `DGM_outer.py`. -/
def runEvolutionLoop (config : DGMConfig) : IO ConcreteArchive := do
  let (initialArchive, startGen) ← initializeRun config
  let testTaskList     ← loadSubset config.polyglot "small"
  let testTaskListMore ← loadSubset config.polyglot "medium"
  IO.println s!"[DGM] Loaded {testTaskList.length} test tasks"
  IO.println s!"[DGM] Starting evolution from generation {startGen}"
  IO.println s!"[DGM] Initial archive size: {initialArchive.entries.length}"
  IO.println s!"[DGM] Best initial score: {initialArchive.bestScore}"

  let separator := String.ofList (List.replicate 50 '=')
  let mut archive := initialArchive
  for gen in List.range (config.maxGenerations - startGen) do
    let genNum := startGen + gen
    IO.println s!"\n{separator}"
    IO.println s!"Generation {genNum}"
    IO.println s!"  Archive: {archive.entries.length} entries, Best: {archive.bestScore}"
    let result ← runGeneration config archive genNum
      testTaskList
      (if config.shallowEval then [] else testTaskListMore)
    archive := result.archive
    IO.println s!"  Results:"
    IO.println s!"    Entries chosen:  {result.selfimproveEntries.length}"
    IO.println s!"    Total attempts:  {result.allResults.length}"
    IO.println s!"    Compiled:        {result.compiledResults.length}"
    IO.println s!"    Archive size:    {archive.entries.length}"
    IO.println s!"    Best score:      {archive.bestScore}"

  IO.println s!"\n{separator}"
  IO.println s!"Evolution complete after {config.maxGenerations} generations"
  IO.println s!"Final archive: {archive.entries.length} entries"
  IO.println s!"Final best score: {archive.bestScore}"
  return archive

/-! ## Verified Evolution Loop -/

/-- A version of the evolution loop that carries verification proofs.
NOTE: Full verification requires connecting IO-level operations
to pure type-level proofs, which involves axioms about external world. -/
structure VerifiedEvolutionResult (spec : AgentSpec) where
  concreteArchive : ConcreteArchive
  generationsRun  : Nat

end DGM.Evolution.Outer
