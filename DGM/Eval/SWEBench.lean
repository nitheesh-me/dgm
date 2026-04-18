import DGM.Types.Basic
import DGM.Utils.Docker
import DGM.Utils.EvalUtils

/-!
# DGM.Eval.SWEBench — SWE-bench Evaluation Harness

Evaluation framework for the SWE-bench benchmark (GitHub issue fixing).
Ported from: `swe_bench/harness.py` and `swe_bench/report.py`
-/
namespace DGM.Eval.SWEBench

open DGM.Types

/-! ## SWE-bench Instance -/

/-- A single SWE-bench instance (GitHub issue). -/
structure SWEInstance where
  /-- Unique instance identifier (e.g., "django__django-12345"). -/
  instanceId : String
  /-- The problem statement (issue body). -/
  problemStatement : String
  /-- Repository name. -/
  repo : String
  /-- Base commit hash. -/
  baseCommit : String
  /-- Test patch to verify the fix. -/
  testPatch : String
  /-- Hints (optional). -/
  hints : Option String := none
  deriving Repr, Inhabited

/-- A prediction (patch) for an SWE-bench instance. -/
structure SWEPrediction where
  /-- Instance ID. -/
  instanceId : String
  /-- The model-generated patch. -/
  modelPatch : String
  /-- The model name that generated it. -/
  modelName : String
  deriving Repr, Inhabited

/-! ## Evaluation -/

/-- Result of evaluating a single instance. -/
structure InstanceEvalResult where
  /-- Instance ID. -/
  instanceId : String
  /-- Whether the patch resolved the issue. -/
  resolved : Bool
  /-- Test results. -/
  testResults : List (String × TestStatus)
  /-- Whether the patch was empty. -/
  emptyPatch : Bool
  deriving Repr, Inhabited

/-- Aggregate evaluation report. -/
structure EvalReport where
  /-- All instance results. -/
  results : List InstanceEvalResult
  /-- Number of resolved instances. -/
  resolvedCount : Nat
  /-- Number of submitted (non-empty patch) instances. -/
  submittedCount : Nat
  /-- Accuracy score (resolved / submitted). -/
  accuracyScore : Float
  deriving Repr, Inhabited

/-- Run evaluation on a set of SWE-bench instances.
Ported from the harness evaluation logic. -/
def runEvaluation (instances : List SWEInstance)
    (predictions : List SWEPrediction) : IO EvalReport := do
  let mut results : List InstanceEvalResult := []

  for inst in instances do
    match predictions.find? (·.instanceId == inst.instanceId) with
    | some pred =>
      if pred.modelPatch.isEmpty then
        results := results ++ [{
          instanceId := inst.instanceId
          resolved := false
          testResults := []
          emptyPatch := true
        }]
      else
        -- In production: set up Docker container, apply patch, run tests
        -- Placeholder: assume not resolved
        results := results ++ [{
          instanceId := inst.instanceId
          resolved := false
          testResults := []
          emptyPatch := false
        }]
    | none =>
      results := results ++ [{
        instanceId := inst.instanceId
        resolved := false
        testResults := []
        emptyPatch := true
      }]

  let resolved := results.filter (·.resolved) |>.length
  let submitted := results.filter (!·.emptyPatch) |>.length
  let accuracy := if submitted > 0 then Float.ofNat resolved / Float.ofNat submitted else 0.0

  return {
    results := results
    resolvedCount := resolved
    submittedCount := submitted
    accuracyScore := accuracy
  }

/-- Convert evaluation report to OverallPerformance.
Bridges the eval module to the core types. -/
def EvalReport.toOverallPerformance (report : EvalReport) : OverallPerformance :=
  { accuracyScore := report.accuracyScore
    totalResolvedInstances := report.resolvedCount
    totalSubmittedInstances := report.submittedCount
    totalUnresolvedIds := report.results.filter (fun r => !r.resolved && !r.emptyPatch) |>.map (·.instanceId)
    totalResolvedIds := report.results.filter (·.resolved) |>.map (·.instanceId)
    totalEmptyPatchIds := report.results.filter (·.emptyPatch) |>.map (·.instanceId)
  }

end DGM.Eval.SWEBench
