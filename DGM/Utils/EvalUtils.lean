import DGM.Types.Basic
import DGM.Utils.LogParsers

/-!
# DGM.Utils.EvalUtils — Evaluation and Scoring Utilities

Ported from: `utils/eval_utils.py`
-/
namespace DGM.Utils.EvalUtils

open DGM.Types

/-- Parse evaluation output for a specific instance.
Ported from `parse_eval_output` in `utils/eval_utils.py`. -/
def parseEvalOutput (instanceId : String) (evalOutput : String)
    : List (String × TestStatus) :=
  -- Dispatch to repo-specific parser
  DGM.Utils.LogParsers.parseLogPytest evalOutput

/-- Calculate the score from a test report.
Ported from `get_report_score` in `utils/eval_utils.py`.
Score = passed_count / total_count -/
def getReportScore (report : List (String × TestStatus)) : Float :=
  if report.isEmpty then 0.0
  else
    let passed := report.filter (·.2 == .passed) |>.length
    Float.ofNat passed / Float.ofNat report.length

/-- Convert message history to a test report.
Ported from `msg_history_to_report` in `utils/eval_utils.py`. -/
def msgHistoryToReport (instanceId : String) (msgHistory : MsgHistory)
    (model : String) : List (String × TestStatus) :=
  -- Extract test output from message history
  -- TODO: Parse tool results from the history
  []

/-- Score tie-breaker using LLM as judge.
Ported from `score_tie_breaker` in `utils/eval_utils.py`.
When multiple responses have the same score, use O1 to judge quality. -/
def scoreTieBreaker (problemStatement : String) (codeDiffs : List String)
    (testReports : List (List (String × TestStatus)))
    (bestScoreIndices : List Nat) : IO Nat := do
  -- TODO: LLM-based tie breaking
  match bestScoreIndices with
  | i :: _ => return i
  | []     => return 0

end DGM.Utils.EvalUtils
