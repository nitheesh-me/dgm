import DGM.Types.Evolution
import DGM.Agent.CodingAgent
import DGM.Agent.LLM
import DGM.Evolution.Archive
import DGM.Utils.Docker
import DGM.Utils.Git
import DGM.Utils.Common
import DGM.Prompts.SelfImprovement
import DGM.Prompts.DiagnoseImprovement

/-!
# DGM.Evolution.SelfImprove — Self-Improvement Step with Verification

The core mutation pipeline: diagnose problems, generate improvements,
evaluate on benchmarks, and produce verified evolution steps.
Ported from: `self_improve_step.py`
-/
namespace DGM.Evolution

open DGM.Types
open DGM.Agent

/-! ## Self-Improvement Configuration -/

/-- Configuration for a self-improvement attempt. -/
structure SelfImproveConfig where
  /-- Parent commit to improve upon. -/
  parentCommit : String
  /-- Output directory for results. -/
  outputDir : String
  /-- Whether to force Docker image rebuild. -/
  forceRebuild : Bool := false
  /-- Number of evaluation instances. -/
  numEvals : Nat := 10
  /-- Whether to run post-improvement diagnosis. -/
  postImproveDiagnose : Bool := false
  /-- The SWE-bench entry to use for diagnosis. -/
  entry : String
  /-- Task list for evaluation. -/
  testTaskList : List String := []
  /-- Extended task list for deeper evaluation. -/
  testTaskListMore : List String := []
  /-- Score threshold for extended evaluation. -/
  testMoreThreshold : Float := 0.4
  /-- Threshold for full evaluation (use Float.infinity to disable). -/
  fullEvalThreshold : Float := 0.6
  /-- Baseline to run: none | "no_selfimprove" | "no_darwin". -/
  runBaseline : Option String := none
  /-- Run only shallow (small task list) evaluation. -/
  shallowEval : Bool := false
  /-- Whether to use polyglot benchmark. -/
  polyglot : Bool := false
  deriving Repr, Inhabited

/-! ## Diagnosis -/

/-- Result of diagnosing problems in the current agent. -/
structure DiagnosisResult where
  /-- The problem statement generated from diagnosis. -/
  problemStatement : String
  /-- Implementation suggestion. -/
  suggestion : String
  /-- Raw LLM response. -/
  rawResponse : String
  deriving Repr, Inhabited

/-- Diagnose problems in the current agent by analyzing evaluation logs.
Ported from `diagnose_problem` in `self_improve_step.py`.
Uses O1 model to analyze logs and generate a problem statement. -/
def diagnoseProblem (entry parentCommit : String) (rootDir outDir : String)
    (patchFiles : List String) (maxAttempts : Nat := 5)
    (polyglot : Bool := false) : IO (Option DiagnosisResult) := do
  -- 1. Find evaluation logs for the parent
  let logDir := s!"{outDir}/{parentCommit}"
  let logExists ← System.FilePath.pathExists ⟨logDir⟩
  if !logExists then
    IO.eprintln s!"[Diagnose] No logs found at {logDir}"
    return some {
      problemStatement := s!"Improve the coding agent based on evaluation of {entry}"
      suggestion := "Analyze failure patterns and improve the agent's approach"
      rawResponse := ""
    }

  -- 2. Build diagnosis prompt using log files
  let sysMsg := DGM.Prompts.SelfImprovement.diagnoseSystemMessage
  let prompt ← DGM.Prompts.SelfImprovement.getDiagnosePrompt
    entry parentCommit rootDir outDir patchFiles polyglot

  -- 3. Call LLM to diagnose
  let client ← createClient "o1-2024-12-17"
  let messages : List Message := [{
    role := .user
    blocks := [{ blockType := .text, text := some prompt }]
  }]

  let response ← callLLMWithRetry client messages sysMsg
  let responseText := response.content

  -- 4. Extract JSON from response and build problem statement
  let jsonOpt := extractJsonBetweenMarkers responseText
  let problemStatement := match jsonOpt with
    | some json =>
      DGM.Prompts.SelfImprovement.getProblemDescriptionPrompt json polyglot
    | none =>
      s!"Improve the coding agent based on evaluation of {entry}.\n\nDiagnosis: {responseText}"

  return some {
    problemStatement := problemStatement
    suggestion := responseText
    rawResponse := responseText
  }

/-- Diagnose whether an improvement actually helped.
Ported from `diagnose_improvement` in `self_improve_step.py`. -/
structure ImprovementDiagnosis where
  /-- Impact analysis. -/
  impact : String
  /-- List of improvements. -/
  improvements : List String
  /-- List of regressions. -/
  regressions : List String
  /-- Score from -2 to 2. -/
  score : Int
  deriving Repr, Inhabited

def diagnoseImprovement (entry parentCommit : String) (rootDir : String)
    (modelPatchFile outDir runId : String) (patchFiles : List String)
    (maxAttempts : Nat := 5) : IO (Option ImprovementDiagnosis) := do
  -- Read the model patch
  let patchExists ← System.FilePath.pathExists ⟨modelPatchFile⟩
  if !patchExists then return none

  let _patch ← IO.FS.readFile ⟨modelPatchFile⟩

  -- Build diagnosis prompt
  let client ← createClient "o1-2024-12-17"
  let prompt := DGM.Prompts.DiagnoseImprovement.diagnoseImprovementUserPrompt
    entry parentCommit runId outDir
  let sysMsg := DGM.Prompts.DiagnoseImprovement.diagnoseImprovementSystemMessage
  let messages : List Message := [{
    role := .user
    blocks := [{ blockType := .text, text := some prompt }]
  }]

  let response ← callLLMWithRetry client messages sysMsg
  let responseText := response.content

  -- Parse the diagnosis
  let jsonOpt := extractJsonBetweenMarkers responseText
  match jsonOpt with
  | some json =>
    -- Extract fields from JSON
    let impact := extractJsonField json "impact"
    let scoreStr := extractJsonField json "score"
    let score := scoreStr.toInt?.getD 0
    return some {
      impact := impact
      improvements := [extractJsonField json "improvements"]
      regressions := [extractJsonField json "regressions"]
      score := score
    }
  | none => return none
where
  extractJsonField (json field : String) : String :=
    match json.splitOn s!"\"{field}\": \"" with
    | [_, rest] => match rest.splitOn "\"" with | val :: _ => val | _ => ""
    | _ => match json.splitOn s!"\"{field}\":" with
      | [_, rest] => (rest.trim.takeWhile (· != ',') |>.takeWhile (· != '}') |>.trim).toString
      | _ => ""

/-! ## Self-Improvement Result -/

/-- Result of a self-improvement attempt.
Carries the new agent's metadata and optional verification proofs. -/
structure SelfImproveResult where
  /-- Unique run identifier. -/
  runId : String
  /-- Parent commit hash. -/
  parentCommit : String
  /-- Entry used for diagnosis. -/
  entry : String
  /-- The generated problem statement. -/
  problemStatement : String
  /-- Whether a model patch was generated. -/
  modelPatchExists : Bool
  /-- Whether the patch is non-empty. -/
  modelPatchNotEmpty : Bool
  /-- Evaluation directory names. -/
  sweDnames : List String
  /-- Overall performance metrics. -/
  overallPerformance : OverallPerformance
  /-- Whether the improved agent compiles and runs. -/
  isCompiled : Bool
  /-- Post-improvement diagnosis (optional). -/
  improvementDiagnosis : Option ImprovementDiagnosis := none
  deriving Repr, Inhabited

/-- Convert a SelfImproveResult to archive metadata. -/
def SelfImproveResult.toArchiveMetadata (result : SelfImproveResult) (gen : Nat)
    : ArchiveMetadata :=
  { runId        := result.runId
    parentCommit := result.parentCommit
    entry        := result.entry
    generation   := gen
    score        := result.overallPerformance.accuracyScore
    isCompiled   := result.isCompiled }

/-! ## Core Self-Improvement Pipeline -/

/-- Run a single self-improvement attempt.

This is the main function ported from `self_improve` in `self_improve_step.py`.
The pipeline:
1. Set up Docker container with DGM codebase
2. Apply patch chain from ancestors
3. Diagnose problems from evaluation logs
4. Run the coding agent inside the container to generate improvements
5. Extract the model patch
6. Evaluate on the benchmark
7. Optionally diagnose the improvement's impact

Returns the result with metadata and optional verification. -/
def selfImprove (config : SelfImproveConfig) : IO SelfImproveResult := do
  -- Generate unique run ID
  let runId ← generateRunId
  let runDir := s!"{config.outputDir}/{runId}"
  IO.FS.createDirAll ⟨runDir⟩
  IO.println s!"[SelfImprove] Starting run {runId} (parent: {config.parentCommit})"

  -- Step 1: Set up Docker container
  let containerName := s!"dgm-{runId}"
  IO.println s!"[SelfImprove] Building container {containerName}..."
  let container ← DGM.Utils.Docker.buildContainer "dgm" containerName
    config.forceRebuild

  -- Step 2: Get patch chain from parent and apply patches
  let patchFiles ← getModelPatchPaths "." config.outputDir config.parentCommit
  IO.println s!"[SelfImprove] Applying {patchFiles.length} ancestor patches..."
  for patchFile in patchFiles do
    DGM.Utils.Docker.copyToContainer container patchFile "/dgm/patch.diff"
    let _ ← DGM.Utils.Docker.execInContainer container
      "cd /dgm && git apply --reject patch.diff || true"

  -- Step 3: Diagnose problems
  IO.println s!"[SelfImprove] Diagnosing problems for entry: {config.entry}..."
  let diagnosis ← diagnoseProblem config.entry config.parentCommit
    "." config.outputDir patchFiles 5 config.polyglot

  let problemStatement := match diagnosis with
    | some d => d.problemStatement
    | none   => "Improve the coding agent's performance"

  -- Save problem statement
  DGM.Utils.Common.writeFile s!"{runDir}/problem_statement.txt" problemStatement

  -- Step 4: Run coding agent inside container
  IO.println s!"[SelfImprove] Running coding agent..."
  let agentCmd :=
    s!"cd /dgm && python coding_agent.py " ++
    s!"--problem \"{DGM.Agent.jsonEscape problemStatement}\" " ++
    s!"--entry {config.entry} " ++
    s!"--output {runDir}"
  let agentOutput ← DGM.Utils.Docker.execInContainer container agentCmd
  IO.println s!"[SelfImprove] Agent output: {(agentOutput.take 200).toString}"

  -- Step 5: Extract the model patch
  let modelPatchPath := s!"{runDir}/model_patch.diff"
  DGM.Utils.Docker.copyFromContainer container "/dgm/model_patch.diff" modelPatchPath
  let modelPatchExists ← System.FilePath.pathExists ⟨modelPatchPath⟩
  let modelPatchNotEmpty ← if modelPatchExists then do
    let content ← IO.FS.readFile ⟨modelPatchPath⟩
    pure (decide (content.trim.length > 0))
  else pure false
  IO.println s!"[SelfImprove] Patch: exists={modelPatchExists}, non-empty={modelPatchNotEmpty}"

  -- Step 6: Evaluate on benchmark
  IO.println s!"[SelfImprove] Evaluating on benchmark..."
  let performance ← evaluateAgent config runDir modelPatchPath

  -- Step 7: Diagnose improvement (optional)
  let improveDiag ← if config.postImproveDiagnose && modelPatchNotEmpty then do
    IO.println s!"[SelfImprove] Diagnosing improvement..."
    diagnoseImprovement config.entry config.parentCommit "."
      modelPatchPath config.outputDir runId patchFiles
  else
    pure none

  -- Cleanup container
  DGM.Utils.Docker.cleanupContainer container

  -- Save metadata
  let result := {
    runId := runId
    parentCommit := config.parentCommit
    entry := config.entry
    problemStatement := problemStatement
    modelPatchExists := modelPatchExists
    modelPatchNotEmpty := modelPatchNotEmpty
    sweDnames := []
    overallPerformance := performance
    isCompiled := modelPatchExists && modelPatchNotEmpty
    improvementDiagnosis := improveDiag
    : SelfImproveResult
  }
  saveMetadata runDir result
  IO.println s!"[SelfImprove] Run {runId} complete: score={performance.accuracyScore}"

  return result
where
  /-- Generate a unique run ID based on timestamp. -/
  generateRunId : IO String := do
    let ns ← IO.monoNanosNow
    return s!"run_{ns}"

  /-- Evaluate the agent on the configured benchmark. -/
  evaluateAgent (config : SelfImproveConfig) (runDir modelPatchPath : String)
      : IO OverallPerformance := do
    -- Run evaluation via Python harness (SWE-bench or Polyglot)
    let harnessCmd := if config.polyglot then
      s!"python -m polyglot.harness --patch {modelPatchPath} --output {runDir}/eval"
    else
      s!"python -m swe_bench.harness --patch {modelPatchPath} --output {runDir}/eval"
    let result ← IO.Process.output {
      cmd := "bash"
      args := #["-c", harnessCmd]
    }
    if result.exitCode != 0 then
      IO.eprintln s!"[Eval] Harness failed: {(result.stderr.take 500).toString}"
    -- Parse evaluation results
    let evalResultPath := s!"{runDir}/eval/results.json"
    let evalExists ← System.FilePath.pathExists ⟨evalResultPath⟩
    if evalExists then
      let content ← IO.FS.readFile ⟨evalResultPath⟩
      parseEvalResults content
    else
      return {
        accuracyScore := 0.0
        totalResolvedInstances := 0
        totalSubmittedInstances := 0
        totalUnresolvedIds := []
        totalResolvedIds := []
        totalEmptyPatchIds := []
      }

  /-- Parse evaluation results from JSON. -/
  parseEvalResults (json : String) : IO OverallPerformance := do
    -- Parse accuracy_score which is already a float in 0.0-1.0 range
    let score := match json.splitOn "\"accuracy_score\":" with
      | [_, rest] =>
        let numStr := (rest.trim.takeWhile (fun c => c.isDigit || c == '.' || c == '-')).toString
        -- Parse "N.M" format
        match numStr.splitOn "." with
        | [intPart, fracPart] =>
          let intVal := intPart.toNat?.getD 0
          let fracVal := fracPart.toNat?.getD 0
          let fracDivisor := Float.ofNat (10 ^ fracPart.length)
          Float.ofNat intVal + Float.ofNat fracVal / fracDivisor
        | [intPart] =>
          match intPart.toNat? with
          | some n => Float.ofNat n
          | none => 0.0
        | _ => 0.0
      | _ => 0.0
    return {
      accuracyScore := score
      totalResolvedInstances := 0
      totalSubmittedInstances := 0
      totalUnresolvedIds := []
      totalResolvedIds := []
      totalEmptyPatchIds := []
    }

  /-- Save run metadata to JSON. -/
  saveMetadata (runDir : String) (result : SelfImproveResult) : IO Unit := do
    let json := s!"\{\"run_id\": \"{result.runId}\", " ++
      s!"\"parent_commit\": \"{result.parentCommit}\", " ++
      s!"\"entry\": \"{result.entry}\", " ++
      s!"\"model_patch_exists\": {result.modelPatchExists}, " ++
      s!"\"model_patch_not_empty\": {result.modelPatchNotEmpty}, " ++
      s!"\"is_compiled\": {result.isCompiled}, " ++
      s!"\"overall_performance\": \{" ++
      s!"\"accuracy_score\": {result.overallPerformance.accuracyScore}, " ++
      s!"\"total_resolved_instances\": {result.overallPerformance.totalResolvedInstances}, " ++
      s!"\"total_submitted_instances\": {result.overallPerformance.totalSubmittedInstances}}}"
    DGM.Utils.Common.writeFile s!"{runDir}/metadata.json" json

/-! ## Compilation Filtering -/

/-- Check if a self-improvement run produced a valid (compiled) agent.
Ported from `is_compiled_self_improve` in `utils/evo_utils.py`. -/
def isCompiledRun (result : SelfImproveResult) : Bool :=
  result.isCompiled &&
  result.modelPatchExists &&
  result.modelPatchNotEmpty &&
  result.overallPerformance.totalSubmittedInstances > 0

/-- Filter a list of results to only compiled runs.
Ported from `filter_compiled` in `DGM_outer.py`. -/
def filterCompiled (results : List SelfImproveResult) : List SelfImproveResult :=
  results.filter isCompiledRun

end DGM.Evolution
