/-!
# DGM.Agent.PolyglotAgent — Multi-Language Coding Agent

Extends the base coding agent with language-specific test commands
for the Polyglot benchmark (C++, Go, Java, JavaScript, Python, Rust).
Ported from: `coding_agent_polyglot.py`
-/

import DGM.Agent.CodingAgent
import DGM.Types.Basic

namespace DGM.Agent

open DGM.Types

/-! ## Language-Specific Test Commands -/

/-- Test commands for each supported language.
Ported from `TEST_COMMANDS` dict in `coding_agent_polyglot.py`. -/
def testCommandsForLanguage : Language → List (List String)
  | .python     => [["pytest", "-rA", "--tb=long"]]
  | .rust       => [["cargo", "test", "--", "--include-ignored"]]
  | .go         => [["go", "test", "./..."]]
  | .javascript => [["npm", "test"]]
  | .cpp        => [["cmake", "--build", "build"], ["ctest", "--test-dir", "build"]]
  | .java       => [["./gradlew", "test"]]

/-- Get the test command as a single bash string. -/
def testCommandString (lang : Language) : String :=
  let cmds := testCommandsForLanguage lang
  let cmdStrs := cmds.map (String.intercalate " ")
  String.intercalate " && " cmdStrs

/-! ## Polyglot Agent Configuration -/

/-- Configuration for the polyglot coding agent.
Extends base config with language information. -/
structure PolyglotAgentConfig extends CodingAgentConfig where
  /-- Programming language of the target repository. -/
  language : Language
  deriving Repr, Inhabited

/-! ## Polyglot Agent -/

/-- The polyglot coding agent.
Extends the base agent with language-aware test execution. -/
structure PolyglotAgent where
  /-- Base coding agent. -/
  base : CodingAgent
  /-- Target language. -/
  language : Language

/-- Build the system prompt for the polyglot agent. -/
def PolyglotAgent.systemPrompt (agent : PolyglotAgent) : String :=
  let langStr := toString agent.language
  if agent.base.config.selfImprove then
    s!"You are an expert {langStr} software engineer improving a coding agent. " ++
    "Use bash and editor tools to make targeted improvements."
  else
    s!"You are an expert {langStr} software engineer. " ++
    "Fix the described issue using the available tools. " ++
    s!"Run tests with: {testCommandString agent.language}"

/-- Build the instruction for the polyglot agent. -/
def PolyglotAgent.buildInstruction (agent : PolyglotAgent) : String :=
  let base := agent.base.buildInstruction
  let langInfo := s!"\n\n## Language: {agent.language}\n\nTest command: `{testCommandString agent.language}`"
  base ++ langInfo

/-- Run the polyglot agent forward pass.
Similar to base `forward` but with language-specific system prompt. -/
def PolyglotAgent.forward (agent : PolyglotAgent) : IO CodingAgentState := do
  let instruction := agent.buildInstruction
  let systemMsg := agent.systemPrompt

  let finalHistory ← chatWithAgent agent.base.client instruction systemMsg agent.base.tools

  let edits ← agent.base.getCurrentEdits

  -- Save chat history
  let content := finalHistory.map (fun msg =>
    let texts := msg.blocks.filterMap (·.text)
    String.intercalate "\n" texts) |> String.intercalate "\n---\n"
  IO.FS.writeFile ⟨agent.base.config.chatHistoryFile⟩ content

  return {
    msgHistory := finalHistory
    currentEdits := edits
    completed := true
  }

/-- Run language-specific tests. -/
def PolyglotAgent.runTests (agent : PolyglotAgent) : IO DGM.Tools.BashResult := do
  let cmd := testCommandString agent.language
  DGM.Tools.executeBash cmd { workDir := some agent.base.config.gitTempDir }

/-- Create a polyglot agent. -/
def mkPolyglotAgent (config : PolyglotAgentConfig) : IO PolyglotAgent := do
  let baseAgent ← mkCodingAgent config.toCodingAgentConfig
  return { base := baseAgent, language := config.language }

end DGM.Agent
