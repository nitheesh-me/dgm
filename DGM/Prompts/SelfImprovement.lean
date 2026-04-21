import DGM.Types.Basic

/-!
# DGM.Prompts.SelfImprovement — Self-Improvement Prompt Templates

Prompt templates and construction for the diagnosis and improvement pipeline.
Ported from: `prompts/self_improvement_prompt.py`
-/
namespace DGM.Prompts.SelfImprovement

/-! ## Coding Agent Summary -/

/-- Summary of the coding agent architecture, provided to the LLM
for self-improvement context.
Ported from `coding_agent_summary` in `prompts/self_improvement_prompt.py`. -/
def codingAgentSummary : String :=
  "The coding agent (coding_agent.py) is an AgenticSystem that solves GitHub issues.\n" ++
  "It uses an LLM (Claude/OpenAI) with bash and editor tools to:\n" ++
  "1. Understand the issue and codebase\n" ++
  "2. Implement a fix using available tools\n" ++
  "3. Run regression tests to validate\n\n" ++
  "Key components:\n" ++
  "- forward(): Main agent loop that constructs instructions and runs chat_with_agent\n" ++
  "- get_current_edits(): Gets git diff of changes\n" ++
  "- get_regression_tests(): Identifies tests that must pass\n" ++
  "- run_regression_tests(): Validates the fix\n\n" ++
  "The agent can be improved by modifying:\n" ++
  "- The system prompt and instructions\n" ++
  "- Tool usage patterns\n" ++
  "- The agent loop structure\n" ++
  "- Error handling and recovery"

/-- Polyglot variant of the agent summary. -/
def codingAgentSummaryPolyglot : String :=
  codingAgentSummary ++ "\n\n" ++
  "The polyglot agent (coding_agent_polyglot.py) extends the base agent with:\n" ++
  "- Language-specific test commands (pytest, cargo test, go test, etc.)\n" ++
  "- Multi-language support: Python, Rust, Go, JavaScript, C++, Java"

/-! ## Diagnosis System Message -/

/-- System message for the diagnosis LLM call.
Ported from `diagnose_system_message`. -/
def diagnoseSystemMessage : String :=
  "You are an expert software engineer analyzing the performance of a coding agent.\n" ++
  "Your task is to identify patterns in the agent's failures and suggest specific improvements.\n\n" ++
  "Analyze the provided evaluation logs and identify:\n" ++
  "1. Common failure patterns\n" ++
  "2. Types of issues the agent struggles with\n" ++
  "3. Tool usage inefficiencies\n" ++
  "4. Specific code changes that would help\n\n" ++
  "Respond with a JSON object containing:\n" ++
  "- \"implementation_suggestion\": Detailed code change suggestion\n" ++
  "- \"problem_description\": A GitHub issue-style description of the improvement"

/-! ## Prompt Construction -/

/-- Construct the diagnosis prompt with evaluation logs (pure version).
Ported from `get_diagnose_prompt_swe`. -/
def buildDiagnosePrompt (entry : String) (evalLogs : List String)
    (currentCode : String) (patches : List String) : String :=
  let logsSection := if evalLogs.isEmpty then
    "No evaluation logs available."
  else
    String.intercalate "\n---\n" evalLogs
  let patchSection := if patches.isEmpty then
    "No previous patches."
  else
    String.intercalate "\n---\n" patches

  s!"## Current Agent Code\n\n```python\n{currentCode}\n```\n\n" ++
  s!"## Evaluation Logs ({entry})\n\n{logsSection}\n\n" ++
  s!"## Previous Improvement Patches\n\n{patchSection}\n\n" ++
  "## Task\n\n" ++
  "Analyze the evaluation logs above and suggest a specific improvement to the coding agent.\n" ++
  "Focus on patterns of failure and provide an actionable implementation suggestion."

/-- Construct problem description from diagnosis response (pure version).
Ported from `get_problem_description_prompt`. -/
def buildProblemDescriptionPrompt (suggestion : String) (description : String)
    (isPolyglot : Bool) : String :=
  let agentSummary := if isPolyglot then codingAgentSummaryPolyglot else codingAgentSummary
  s!"## Agent Architecture\n\n{agentSummary}\n\n" ++
  s!"## Improvement Description\n\n{description}\n\n" ++
  s!"## Implementation Suggestion\n\n{suggestion}\n\n" ++
  "Please implement this improvement in the coding agent."

/-- Construct problem description from a JSON string response.
Extracts implementation_suggestion and problem_description from JSON. -/
def getProblemDescriptionPrompt (jsonResponse : String) (isPolyglot : Bool) : String :=
  let suggestion := match jsonResponse.splitOn "\"implementation_suggestion\": \"" with
    | [_, rest] => match rest.splitOn "\"" with | val :: _ => val | _ => jsonResponse
    | _ => jsonResponse
  let description := match jsonResponse.splitOn "\"problem_description\": \"" with
    | [_, rest] => match rest.splitOn "\"" with | val :: _ => val | _ => ""
    | _ => ""
  buildProblemDescriptionPrompt suggestion description isPolyglot

/-! ## Log Processing -/

/-- Read and filter a markdown log file.
Ported from `read_mdlog_file`. -/
def readMdLogFile (filepath : String) (doFilter : Bool := true) : IO String := do
  let content ← IO.FS.readFile ⟨filepath⟩
  if doFilter then
    let lines := content.splitOn "\n"
    let filtered := lines.map fun line =>
      if line.length > 5000 then (line.take 5000).toString ++ "... [truncated]"
      else line
    return String.intercalate "\n" filtered
  else
    return content

/-- Find evaluation log files for a given entry and commit.
Ported from `find_selfimprove_eval_logs`. -/
def findEvalLogs (_entry outDir : String) (commitId : String := "initial")
    (doFilter : Bool := true) : IO (List String) := do
  let logDir := s!"{outDir}/{commitId}/logs"
  let dirExists ← System.FilePath.pathExists ⟨logDir⟩
  if !dirExists then return []

  let dirEntries ← System.FilePath.readDir ⟨logDir⟩
  let logFiles := dirEntries.toList
    |>.filter (·.fileName.endsWith ".md")
    |>.map (fun e => s!"{logDir}/{e.fileName}")

  let mut logs : List String := []
  for file in logFiles do
    let content ← readMdLogFile file doFilter
    logs := logs ++ [content]
  return logs

/-- Get the current agent code (possibly modified by previous patches).
Ported from `get_current_code`. -/
def getCurrentCode (_commit rootDir _outDir : String) : IO String := do
  let codePath := s!"{rootDir}/coding_agent.py"
  let pathExists ← System.FilePath.pathExists ⟨codePath⟩
  if pathExists then
    IO.FS.readFile ⟨codePath⟩
  else
    return "# coding_agent.py not found"

/-- Construct the diagnosis prompt given file paths (for SelfImprove pipeline).
Loads logs and code from disk. -/
def getDiagnosePrompt (entry commitId rootDir outDir : String)
    (patchFiles : List String) (_polyglot : Bool) : IO String := do
  let evalLogs ← findEvalLogs entry outDir commitId
  let currentCode ← getCurrentCode commitId rootDir outDir
  let patches ← patchFiles.mapM fun f => do
    let fExists ← System.FilePath.pathExists ⟨f⟩
    if fExists then IO.FS.readFile ⟨f⟩ else pure ""
  return buildDiagnosePrompt entry evalLogs currentCode patches

end DGM.Prompts.SelfImprovement
