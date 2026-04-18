/-!
# DGM.Prompts.DiagnoseImprovement — Improvement Diagnosis Prompts

Prompts for evaluating whether a code change improved agent performance.
Ported from: `prompts/diagnose_improvement_prompt.py`
-/

namespace DGM.Prompts.DiagnoseImprovement

/-! ## System Message -/

/-- System message for improvement diagnosis.
Ported from the system message in `diagnose_improvement_prompt.py`. -/
def diagnoseImprovementSystemMessage (agentCode patch : String)
    (testPatches answerPatches : List String) : String :=
  s!"You are an expert software engineer evaluating the impact of a code change.\n\n" ++
  s!"## Modified Agent Code\n\n```python\n{agentCode}\n```\n\n" ++
  s!"## Applied Patch\n\n```diff\n{patch}\n```\n\n" ++
  s!"## Test Patches Applied\n\n" ++
  String.intercalate "\n---\n" testPatches ++ "\n\n" ++
  s!"## Answer Patches Applied\n\n" ++
  String.intercalate "\n---\n" answerPatches ++ "\n\n" ++
  "Analyze whether this patch improved the agent's performance."

/-! ## User Prompt -/

/-- User prompt comparing before/after performance.
Ported from the user prompt construction. -/
def diagnoseImprovementUserPrompt (beforeLogs afterLogs : List String)
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

end DGM.Prompts.DiagnoseImprovement
