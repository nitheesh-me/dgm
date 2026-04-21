/-!
# DGM.Prompts.DiagnoseImprovement — Improvement Diagnosis Prompts

Prompts for evaluating whether a code change improved agent performance.
Ported from: `prompts/diagnose_improvement_prompt.py`
-/

namespace DGM.Prompts.DiagnoseImprovement

/-! ## System Message -/

/-- System message for improvement diagnosis (full version with code context).
Ported from the system message in `diagnose_improvement_prompt.py`. -/
def diagnoseImprovementSystemMessageFull (agentCode patch : String)
    (testPatches answerPatches : List String) : String :=
  s!"You are an expert software engineer evaluating the impact of a code change.\n\n" ++
  s!"## Modified Agent Code\n\n```python\n{agentCode}\n```\n\n" ++
  s!"## Applied Patch\n\n```diff\n{patch}\n```\n\n" ++
  s!"## Test Patches Applied\n\n" ++
  String.intercalate "\n---\n" testPatches ++ "\n\n" ++
  s!"## Answer Patches Applied\n\n" ++
  String.intercalate "\n---\n" answerPatches ++ "\n\n" ++
  "Analyze whether this patch improved the agent's performance."

/-- Simplified system message for improvement diagnosis. -/
def diagnoseImprovementSystemMessage : String :=
  "You are an expert software engineer evaluating the impact of a code change.\n\n" ++
  "Analyze the performance comparison and determine if the improvement was beneficial.\n\n" ++
  "Respond with a JSON object containing:\n" ++
  "- \"impact\": Thorough analysis of the change's impact\n" ++
  "- \"improvements\": List of specific improvements observed\n" ++
  "- \"regressions\": List of any regressions\n" ++
  "- \"score\": A score from -2 (major regression) to 2 (major improvement)"

/-! ## User Prompt -/

/-- User prompt comparing before/after performance (with full log data).
Ported from the user prompt construction. -/
def diagnoseImprovementUserPromptFull (beforeLogs afterLogs : List String)
    (beforeScore afterScore : Float) : String :=
  let beforeSection := String.intercalate "\n---\n" beforeLogs
  let afterSection := String.intercalate "\n---\n" afterLogs
  s!"## Performance BEFORE Patch (score: {beforeScore})\n\n{beforeSection}\n\n" ++
  s!"## Performance AFTER Patch (score: {afterScore})\n\n{afterSection}\n\n" ++
  "## Task\n\n" ++
  "Compare the agent's performance before and after the patch.\n" ++
  "Respond with a JSON object containing:\n" ++
  "- \"impact\": Thorough analysis of the change's impact\n" ++
  "- \"improvements\": List of specific improvements observed\n" ++
  "- \"regressions\": List of any regressions\n" ++
  "- \"score\": A score from -2 (major regression) to 2 (major improvement)"

/-- Simplified user prompt for improvement diagnosis (used by SelfImprove pipeline). -/
def diagnoseImprovementUserPrompt (entry parentCommit runId outDir : String) : String :=
  s!"Compare the performance of the coding agent before and after improvement.\n\n" ++
  s!"Entry: {entry}\n" ++
  s!"Parent commit: {parentCommit}\n" ++
  s!"New run ID: {runId}\n" ++
  s!"Output directory: {outDir}\n\n" ++
  "Analyze the evaluation logs in the output directory for both the parent and the new run.\n" ++
  "Determine if the improvement was beneficial."

end DGM.Prompts.DiagnoseImprovement
