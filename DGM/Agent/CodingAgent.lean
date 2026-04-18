/-!
# DGM.Agent.CodingAgent — SWE-bench Coding Agent

The main agent for solving GitHub issues. Wraps an LLM with tool access
and git operations.
Ported from: `coding_agent.py`
-/

import DGM.Agent.LLM
import DGM.Tools.Tool
import DGM.Types.Basic
import DGM.Utils.Git

namespace DGM.Agent

open DGM.Types
open DGM.Tools

/-! ## Agent Configuration -/

/-- Configuration for the coding agent.
Corresponds to the `AgenticSystem.__init__` parameters. -/
structure CodingAgentConfig where
  /-- The problem statement (GitHub issue). -/
  problemStatement : String
  /-- Path to the cloned repository. -/
  gitTempDir : String
  /-- Base commit hash to compare against. -/
  baseCommit : String
  /-- Path to save chat history markdown. -/
  chatHistoryFile : String
  /-- Test execution instructions. -/
  testDescription : Option String := none
  /-- Whether running in self-improvement mode. -/
  selfImprove : Bool := false
  /-- SWE issue identifier. -/
  instanceId : Option String := none
  deriving Repr, Inhabited

/-! ## Agent State -/

/-- Mutable state of the coding agent during execution. -/
structure CodingAgentState where
  /-- Conversation history with the LLM. -/
  msgHistory : MsgHistory := []
  /-- Current git diff against base commit. -/
  currentEdits : String := ""
  /-- Whether the agent has completed. -/
  completed : Bool := false
  /-- Regression test summary. -/
  regressionTests : Option String := none
  deriving Inhabited

/-! ## The Coding Agent -/

/-- The coding agent system.
Ported from `class AgenticSystem` in `coding_agent.py`. -/
structure CodingAgent where
  /-- Agent configuration. -/
  config : CodingAgentConfig
  /-- LLM client. -/
  client : LLMClient
  /-- Tool registry. -/
  tools : ToolRegistry

/-- Get the current edits as a git diff.
Ported from `AgenticSystem.get_current_edits`. -/
def CodingAgent.getCurrentEdits (agent : CodingAgent) : IO String :=
  DGM.Utils.Git.diffVersusCommit agent.config.gitTempDir agent.config.baseCommit

/-- Build the system prompt for the coding agent. -/
def CodingAgent.systemPrompt (agent : CodingAgent) : String :=
  if agent.config.selfImprove then
    "You are an expert software engineer tasked with improving a coding agent's implementation. " ++
    "You have access to bash and editor tools. Make targeted improvements to the codebase."
  else
    "You are an expert software engineer. You will be given a GitHub issue and a cloned repository. " ++
    "Use the available tools (bash, editor) to understand the issue and implement a fix. " ++
    "Make minimal, targeted changes."

/-- Build the user instruction from the config. -/
def CodingAgent.buildInstruction (agent : CodingAgent) : String :=
  let base := s!"## Problem Statement\n\n{agent.config.problemStatement}"
  let testInfo := match agent.config.testDescription with
    | some desc => s!"\n\n## Test Information\n\n{desc}"
    | none      => ""
  let instanceInfo := match agent.config.instanceId with
    | some id => s!"\n\nInstance ID: {id}"
    | none    => ""
  base ++ testInfo ++ instanceInfo

/-- Run the coding agent forward pass.

This is the main entry point, ported from `AgenticSystem.forward()`.
1. Constructs the instruction from the problem statement
2. Runs the agentic chat loop (LLM + tools)
3. Extracts the patch from the resulting edits
4. Saves the chat history

Returns the final state including the patch. -/
def CodingAgent.forward (agent : CodingAgent) : IO CodingAgentState := do
  let instruction := agent.buildInstruction
  let systemMsg := agent.systemPrompt

  -- Run the agentic chat loop
  let finalHistory ← chatWithAgent agent.client instruction systemMsg agent.tools

  -- Get the resulting edits
  let edits ← agent.getCurrentEdits

  -- Save chat history
  saveChatHistory agent.config.chatHistoryFile finalHistory

  return {
    msgHistory := finalHistory
    currentEdits := edits
    completed := true
  }
where
  /-- Save the chat history to a markdown file. -/
  saveChatHistory (path : String) (history : MsgHistory) : IO Unit := do
    let content := formatHistory history
    IO.FS.writeFile ⟨path⟩ content
  /-- Format message history as markdown. -/
  formatHistory (history : MsgHistory) : String :=
    let parts := history.map fun msg =>
      let roleStr := match msg.role with
        | .user      => "## User"
        | .assistant => "## Assistant"
        | .system    => "## System"
      let contentStr := msg.blocks.filterMap (·.text) |> String.intercalate "\n"
      s!"{roleStr}\n\n{contentStr}\n"
    String.intercalate "\n---\n\n" parts

/-! ## Regression Testing -/

/-- Generate regression test summary using the LLM.
Ported from `AgenticSystem.get_regression_tests`. -/
def CodingAgent.getRegressionTests (agent : CodingAgent) (edits : String) : IO String := do
  let prompt := s!"Given the following code changes, identify the key regression tests that should be run:\n\n{edits}"
  let response ← callLLMWithRetry agent.client
    [{ role := .user, blocks := [{ blockType := .text, text := some prompt }] }]
    "You are a testing expert. Identify regression tests for code changes."
  return response.content

/-- Run regression tests and return the report.
Ported from `AgenticSystem.run_regression_tests`. -/
def CodingAgent.runRegressionTests (agent : CodingAgent) (testSummary : String)
    : IO (List (String × TestStatus)) := do
  -- Execute tests via bash tool
  let result ← DGM.Tools.executeBash s!"cd {agent.config.gitTempDir} && pytest -rA --tb=short"
    { workDir := some agent.config.gitTempDir }
  -- Parse test output
  let _output := result.stdout
  -- TODO: Use log parsers to extract test results
  return []

/-! ## Agent Construction -/

/-- Create a coding agent with default configuration.
Selects the appropriate model based on self-improve mode. -/
def mkCodingAgent (config : CodingAgentConfig) : IO CodingAgent := do
  let modelName := if config.selfImprove then defaultOpenAIModel else defaultClaudeModel
  let client ← createClient modelName
  let tools := ToolRegistry.empty
    |>.register DGM.Tools.bashToolEntry
    |>.register DGM.Tools.editToolEntry
  return { config := config, client := client, tools := tools }

end DGM.Agent
