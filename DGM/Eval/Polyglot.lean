import DGM.Types.Basic
import DGM.Utils.Docker

/-!
# DGM.Eval.Polyglot — Polyglot Benchmark Evaluation Harness

Multi-language evaluation framework supporting C++, Go, Java, JavaScript, Python, Rust.
Ported from: `polyglot/harness.py` and `polyglot/run_evaluation.py`
-/
namespace DGM.Eval.Polyglot

open DGM.Types

/-! ## Polyglot Instance -/

/-- A single polyglot benchmark instance. -/
structure PolyglotInstance where
  /-- Unique instance identifier. -/
  instanceId : String
  /-- The problem statement. -/
  problemStatement : String
  /-- Repository name. -/
  repo : String
  /-- Programming language. -/
  language : Language
  /-- Base commit hash. -/
  baseCommit : String
  /-- Test command to run. -/
  testCommand : String
  deriving Repr, Inhabited

/-- A prediction for a polyglot instance. -/
structure PolyglotPrediction where
  instanceId : String
  modelPatch : String
  modelName  : String
  deriving Repr, Inhabited

/-! ## Evaluation -/

/-- Result of evaluating a single polyglot instance. -/
structure PolyglotEvalResult where
  instanceId : String
  language   : Language
  resolved   : Bool
  testResults : List (String × TestStatus)
  emptyPatch : Bool
  deriving Repr, Inhabited

/-- Aggregate polyglot evaluation report. -/
structure PolyglotReport where
  results       : List PolyglotEvalResult
  resolvedCount : Nat
  submittedCount : Nat
  accuracyScore : Float
  /-- Per-language breakdown. -/
  perLanguage   : List (Language × Nat × Nat)  -- (lang, resolved, total)
  deriving Repr, Inhabited

/-- Run polyglot evaluation.
Ported from `polyglot/harness.py`. -/
def runEvaluation (instances : List PolyglotInstance)
    (predictions : List PolyglotPrediction) : IO PolyglotReport := do
  let mut results : List PolyglotEvalResult := []

  for inst in instances do
    match predictions.find? (·.instanceId == inst.instanceId) with
    | some pred =>
      let empty := pred.modelPatch.isEmpty
      -- In production: Docker container setup, patch, test
      results := results ++ [{
        instanceId := inst.instanceId
        language := inst.language
        resolved := false
        testResults := []
        emptyPatch := empty
      }]
    | none =>
      results := results ++ [{
        instanceId := inst.instanceId
        language := inst.language
        resolved := false
        testResults := []
        emptyPatch := true
      }]

  let resolved := results.filter (·.resolved) |>.length
  let submitted := results.filter (!·.emptyPatch) |>.length
  let accuracy := if submitted > 0 then Float.ofNat resolved / Float.ofNat submitted else 0.0

  -- Per-language breakdown
  let languages := [Language.python, .rust, .go, .javascript, .cpp, .java]
  let perLang := languages.map fun lang =>
    let langResults := results.filter (·.language == lang)
    let langResolved := langResults.filter (·.resolved) |>.length
    (lang, langResolved, langResults.length)

  return {
    results := results
    resolvedCount := resolved
    submittedCount := submitted
    accuracyScore := accuracy
    perLanguage := perLang
  }

/-- Convert polyglot report to OverallPerformance. -/
def PolyglotReport.toOverallPerformance (report : PolyglotReport) : OverallPerformance :=
  { accuracyScore := report.accuracyScore
    totalResolvedInstances := report.resolvedCount
    totalSubmittedInstances := report.submittedCount
    totalUnresolvedIds := report.results.filter (fun r => !r.resolved && !r.emptyPatch) |>.map (·.instanceId)
    totalResolvedIds := report.results.filter (·.resolved) |>.map (·.instanceId)
    totalEmptyPatchIds := report.results.filter (·.emptyPatch) |>.map (·.instanceId)
  }

end DGM.Eval.Polyglot
