/-!
# DGM.Agent.MockLLM — Mock LLM Responses for Testing Without API Keys

When API keys are not available, this module provides deterministic but varied
mock responses that simulate real LLM behavior. Responses are selected based on
a hash of the input prompt to provide consistent but diverse outputs.

This allows the full DGM pipeline to be exercised and validated without
incurring API costs or requiring credentials.
-/

import DGM.Types.Basic

namespace DGM.Agent.MockLLM

open DGM.Types

/-! ## Response Pools -/

/-- Pre-selected diagnosis responses simulating O1 analysis of agent failures.
Each is a valid JSON response matching the expected format. -/
def diagnosisResponses : Array String := #[
  "```json\n{\"implementation_suggestion\": \"Add retry logic with exponential backoff when bash tool execution fails due to transient errors. Wrap the execute_bash call in a retry loop with max_attempts=3 and initial_delay=1s.\", \"problem_description\": \"The coding agent fails on intermittent bash execution errors without retrying. Add robust retry handling for tool execution.\"}```",
  "```json\n{\"implementation_suggestion\": \"Improve the system prompt to instruct the agent to always read the failing test before attempting a fix. Add an explicit step: 'First, read and understand the failing test case.'\", \"problem_description\": \"The agent often attempts fixes without understanding the test expectations. Improve the prompt to encourage test-first debugging.\"}```",
  "```json\n{\"implementation_suggestion\": \"Add a pre-processing step that parses the issue to extract key information: affected file paths, error messages, and expected behavior. Use this structured info in the system prompt.\", \"problem_description\": \"The agent struggles with long, complex issue descriptions. Add issue parsing to extract structured information before solving.\"}```",
  "```json\n{\"implementation_suggestion\": \"Modify the agent loop to include a self-review step after generating a patch. The agent should run tests and review failures before declaring completion.\", \"problem_description\": \"The agent generates patches without self-validation. Add an explicit test-and-review cycle before completion.\"}```",
  "```json\n{\"implementation_suggestion\": \"Increase context window utilization by summarizing long tool outputs instead of truncating them. Use a rolling summary of bash output when it exceeds 5000 characters.\", \"problem_description\": \"The agent loses important context when tool outputs are truncated. Implement smarter context management with summarization.\"}```"
]

/-- Pre-selected improvement diagnosis responses. -/
def improvementDiagnosisResponses : Array String := #[
  "```json\n{\"impact\": \"The change improved error handling in tool execution, reducing failures on transient issues.\", \"improvements\": [\"Reduced bash tool failures by 30%\", \"Better error recovery in agent loop\"], \"regressions\": [\"Slight increase in execution time due to retries\"], \"score\": 1}```",
  "```json\n{\"impact\": \"The prompt change led to more structured problem-solving but slightly slower responses.\", \"improvements\": [\"Agent now reads tests first\", \"Better understanding of expected behavior\"], \"regressions\": [\"5% longer average conversation length\"], \"score\": 1}```",
  "```json\n{\"impact\": \"The change had minimal effect on overall performance.\", \"improvements\": [\"Slightly cleaner code structure\"], \"regressions\": [\"No significant regressions\"], \"score\": 0}```",
  "```json\n{\"impact\": \"Mixed results - some improvements but also introduced a regression in test handling.\", \"improvements\": [\"Better file path detection\"], \"regressions\": [\"Regression in handling multi-file patches\"], \"score\": -1}```"
]

/-- Pre-selected coding agent responses for tool use scenarios. -/
def codingAgentResponses : Array String := #[
  "I'll start by examining the repository structure and understanding the failing test.\n\nLet me first look at the test file to understand what's expected.",
  "Based on my analysis of the issue, I need to modify the relevant source file. Let me first read the current implementation.",
  "I've identified the root cause. The issue is in the error handling logic. Let me implement a fix.",
  "The test is now passing. Let me verify there are no regressions by running the full test suite.",
  "I've completed my changes. The fix addresses the core issue by improving the error handling path."
]

/-- Pre-selected self-improvement code patches. -/
def selfImprovementPatches : Array String := #[
  "--- a/coding_agent.py\n+++ b/coding_agent.py\n@@ -50,6 +50,10 @@ class AgenticSystem:\n     def forward(self):\n+        # Enhanced: Add structured issue parsing\n+        issue_info = self._parse_issue(self.problem_statement)\n+        self.instruction = self._build_enhanced_instruction(issue_info)\n+\n         chat_with_agent(\n             self.client,\n             self.instruction,",
  "--- a/coding_agent.py\n+++ b/coding_agent.py\n@@ -30,6 +30,8 @@ class AgenticSystem:\n     def __init__(self, problem_statement, git_tempdir, base_commit):\n         self.problem_statement = problem_statement\n+        self.max_retries = 3\n+        self.retry_delay = 1.0\n         self.git_tempdir = git_tempdir"
]

/-! ## Hash-based Selection -/

/-- Simple string hash for deterministic but varied selection.
Uses FNV-1a-inspired hash for good distribution. -/
def stringHash (s : String) : Nat :=
  s.foldl (fun hash c =>
    let hash := Nat.xor hash c.toNat
    -- Simulate FNV multiply: hash * 16777619
    -- Use a simpler multiply to avoid overflow complexity
    (hash * 31 + 17) % 1000000007
  ) 2166136261 % 1000000007

/-- Select a response from a pool based on the input prompt hash. -/
def selectResponse (pool : Array String) (prompt : String) : String :=
  if h : pool.size > 0 then
    let idx := stringHash prompt % pool.size
    have : idx < pool.size := Nat.mod_lt _ h
    pool[idx]
  else ""

/-! ## Mock LLM Client -/

/-- Whether mock mode is active (set once at startup). -/
structure MockConfig where
  /-- Whether mock mode is enabled. -/
  enabled : Bool := false
  /-- Seed for reproducibility. Influences response selection. -/
  seed : Nat := 42
  deriving Repr, Inhabited

/-- Check if we should use mock mode based on environment. -/
def shouldUseMock : IO Bool := do
  let anthropic ← IO.getEnv "ANTHROPIC_API_KEY"
  let openai ← IO.getEnv "OPENAI_API_KEY"
  let deepseek ← IO.getEnv "DEEPSEEK_API_KEY"
  -- Use mock if NO API keys are set
  match (anthropic, openai, deepseek) with
  | (none, none, none) => return true
  | _ => return false

/-- Generate a mock LLM response based on the messages and system context.

Selects from pre-defined response pools based on the prompt content:
- If the system message mentions "diagnosis" → use diagnosis pool
- If the system message mentions "improvement" → use improvement pool
- Otherwise → use coding agent pool

The response is deterministically selected based on a hash of the prompt
for reproducibility, but varies based on content for realism. -/
def mockLLMCall (messages : List Message) (systemMessage : String)
    (tools : List ToolInfo := []) : IO (String × String × List (String × String × String)) := do
  -- Combine all message text for hashing
  let promptText := messages.foldl (fun acc msg =>
    acc ++ (msg.blocks.filterMap (·.text) |> String.intercalate "\n")
  ) systemMessage

  IO.eprintln "[MockLLM] Using mock response (no API keys configured)"

  -- Select response pool based on context
  let (content, stopReason) :=
    if systemMessage.containsSubstr "impact" || systemMessage.containsSubstr "evaluating" then
      -- Improvement diagnosis
      (selectResponse improvementDiagnosisResponses promptText, "end_turn")
    else if systemMessage.containsSubstr "diagnos" || systemMessage.containsSubstr "analyzing" then
      -- Problem diagnosis
      (selectResponse diagnosisResponses promptText, "end_turn")
    else if !tools.isEmpty then
      -- Tool-using agent: occasionally generate a tool call
      let hash := stringHash promptText
      if hash % 5 == 0 then
        -- Return a tool use response ~20% of the time
        let toolName := match tools.head? with
          | some t => t.name
          | none => "bash"
        let toolInput := if toolName == "bash" then
          "{\"command\": \"find . -name '*.py' -type f | head -20\"}"
        else
          "{\"command\": \"view\", \"path\": \"/repo/README.md\"}"
        -- For tool use, we return content with tool info embedded
        (s!"Let me explore the codebase first.\n\n<tool_use>\n{{\"tool_name\": \"{toolName}\", \"tool_input\": {toolInput}}}\n</tool_use>", "tool_use")
      else
        (selectResponse codingAgentResponses promptText, "end_turn")
    else
      -- Generic response
      (selectResponse codingAgentResponses promptText, "end_turn")

  return (content, stopReason, [])

end DGM.Agent.MockLLM
