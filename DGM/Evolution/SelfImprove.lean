/-!
# DGM.Evolution.SelfImprove — Self-Improvement Step with Verification

The core mutation pipeline: diagnose problems, generate improvements,
evaluate on benchmarks, and produce verified evolution steps.
Ported from: `self_improve_step.py`
-/

import DGM.Types.Evolution
import DGM.Agent.CodingAgent
import DGM.Agent.LLM
import DGM.Evolution.Archive
import DGM.Utils.Docker
import DGM.Utils.Git

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
  postImproveDiagnose : Bool := true
  /-- The SWE-bench entry to use for diagnosis. -/
  entry : String
  /-- Task list for evaluation. -/
  testTaskList : List String := []
  /-- Extended task list for deeper evaluation. -/
  testTaskListMore : List String := []
  /-- Score threshold for extended evaluation. -/
  testMoreThreshold : Float := 0.5
  /-- Threshold for full evaluation. -/
  fullEvalThreshold : Float := 0.6
  /-- Whether to run baseline comparison. -/
  runBaseline : Bool := false
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
Ported from `diagnose_problem` in `self_improve_step.py`. -/
def diagnoseProblem (entry parentCommit : String) (rootDir outDir : String)
    (patchFiles : List String) (maxAttempts : Nat := 5)
    (polyglot : Bool := false) : IO (Option DiagnosisResult) := do
  -- 1. Find evaluation logs for the parent
  -- 2. Process logs to identify failure patterns
  -- 3. Use LLM to diagnose the root cause
  -- 4. Generate a problem statement for improvement
  let _logDir := s!"{outDir}/{parentCommit}"
  -- TODO: Implement log finding and processing
  return some {
    problemStatement := s!"Improve the coding agent based on evaluation of {entry}"
    suggestion := "Analyze failure patterns and improve the agent's approach"
    rawResponse := ""
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
  -- TODO: Compare before/after performance
  return none

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
2. Diagnose problems from evaluation logs
3. Run the coding agent inside the container to generate improvements
4. Extract the model patch
5. Evaluate on the benchmark
6. Optionally diagnose the improvement's impact

Returns the result with metadata and optional verification. -/
def selfImprove (config : SelfImproveConfig) : IO SelfImproveResult := do
  -- Generate unique run ID
  let runId ← generateRunId

  -- Step 1: Set up Docker container
  let _container ← DGM.Utils.Docker.buildContainer "dgm" s!"dgm-{runId}"
    config.forceRebuild

  -- Step 2: Get patch chain from parent
  let patchFiles ← getModelPatchPaths "." config.outputDir config.parentCommit

  -- Step 3: Diagnose problems
  let diagnosis ← diagnoseProblem config.entry config.parentCommit
    "." config.outputDir patchFiles 5 config.polyglot

  let problemStatement := match diagnosis with
    | some d => d.problemStatement
    | none   => "Improve the coding agent's performance"

  -- Step 4: Run coding agent inside container
  -- In production: docker exec + coding_agent.py
  let modelPatchExists := false
  let modelPatchNotEmpty := false

  -- Step 5: Evaluate on benchmark
  let performance : OverallPerformance := {
    accuracyScore := 0.0
    totalResolvedInstances := 0
    totalSubmittedInstances := 0
    totalUnresolvedIds := []
    totalResolvedIds := []
    totalEmptyPatchIds := []
  }

  -- Step 6: Diagnose improvement (optional)
  let improveDiag ← if config.postImproveDiagnose then
    diagnoseImprovement config.entry config.parentCommit "."
      s!"{config.outputDir}/{runId}/model_patch.diff"
      config.outputDir runId patchFiles
  else
    pure none

  return {
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
  }
where
  /-- Generate a unique run ID based on timestamp. -/
  generateRunId : IO String := do
    -- Simple timestamp-based ID
    return s!"run_{← IO.monoNanosNow}"

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
