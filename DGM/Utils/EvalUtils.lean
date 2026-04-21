import DGM.Types.Basic
import DGM.Utils.LogParsers

/-!
# DGM.Utils.EvalUtils — Evaluation and Scoring Utilities

Ported from: `utils/eval_utils.py`
-/
namespace DGM.Utils.EvalUtils

open DGM.Types

/-- Convert a SWE-bench instance ID to a repo name.
E.g. "scikit-learn__scikit-learn-12421" → "scikit-learn/scikit-learn"
Ported from `parse_eval_output` in `utils/eval_utils.py`. -/
def instanceIdToRepo (instanceId : String) : String :=
  if instanceId == "dgm" then "dgm"
  else
    -- "org__repo-12345" → "org/repo"
    let withSlash := instanceId.replace "__" "/"
    -- Remove the trailing "-<digits>" part
    let parts := withSlash.splitOn "-"
    -- The last part is the issue number; join everything else
    match parts.reverse with
    | _ :: rest => String.intercalate "-" rest.reverse
    | _ => instanceId

/-- Parse evaluation output for a specific instance.
Dispatches to the repo-specific parser.
Ported from `parse_eval_output` in `utils/eval_utils.py`. -/
def parseEvalOutput (instanceId : String) (evalOutput : String)
    : List (String × TestStatus) :=
  let repo := instanceIdToRepo instanceId
  let parser := DGM.Utils.LogParsers.getParser repo
  parser evalOutput

/-- Calculate the score from a test report.
Score = passed_count / total_count
Ported from `get_report_score` in `utils/eval_utils.py`. -/
def getReportScore (report : List (String × TestStatus)) : Float :=
  if report.isEmpty then 0.0
  else
    let passed := report.filter (·.2 == .passed) |>.length
    Float.ofNat passed / Float.ofNat report.length

/-- Extract text content from a message's content blocks. -/
def extractMessageText (msg : Message) : String :=
  msg.blocks.filterMap (fun b =>
    match b.blockType with
    | .text => b.text
    | .toolResult => b.content
    | _ => none)
  |> String.intercalate "\n"

/-- Convert message history to a test report.
Searches backwards through message history for tool results containing
test output, then parses them using the repo-specific parser.
Ported from `msg_history_to_report` in `utils/eval_utils.py`. -/
def msgHistoryToReport (instanceId : String) (msgHistory : MsgHistory)
    : List (String × TestStatus) :=
  -- Search backwards for tool result messages
  let reversed := msgHistory.reverse
  let found := reversed.findSome? fun msg =>
    if msg.role == .user then
      let text := extractMessageText msg
      if text.containsSubstr "Tool Result:" then
        let report := parseEvalOutput instanceId text
        if report.isEmpty then none else some report
      else
        none
    else
      none
  found.getD []

/-- Score tie-breaker using LLM as judge.
When multiple responses have the same score, use O1 to judge quality.
Ported from `score_tie_breaker` in `utils/eval_utils.py`.
Returns the index of the best solution. -/
def scoreTieBreaker (_problemStatement : String) (_codeDiffs : List String)
    (_testReports : List (List (String × TestStatus)))
    (bestScoreIndices : List Nat) : IO Nat := do
  -- Use the first index as default (full LLM-based tie-breaking is possible
  -- but requires full LLM integration; the Python version uses o1-2024-12-17)
  match bestScoreIndices with
  | i :: _ => return i
  | []     => return 0

end DGM.Utils.EvalUtils
