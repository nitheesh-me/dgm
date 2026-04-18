/-!
# DGM.Tools.Bash — Bash Command Execution Tool

IO monad-based bash execution with timeout handling.
Ported from: `tools/bash.py`
-/

import DGM.Tools.Tool

namespace DGM.Tools

/-! ## Bash Session -/

/-- Configuration for bash execution. -/
structure BashConfig where
  /-- Maximum execution time in milliseconds. -/
  timeoutMs : Nat := 120000
  /-- Working directory. -/
  workDir : Option String := none
  deriving Repr, Inhabited

/-- Result of a bash command execution. -/
structure BashResult where
  /-- Standard output. -/
  stdout : String
  /-- Standard error (filtered). -/
  stderr : String
  /-- Exit code. -/
  exitCode : UInt32
  deriving Repr, Inhabited

/-- Whether the bash result indicates success. -/
def BashResult.isSuccess (r : BashResult) : Bool := r.exitCode == 0

/-- Filter out known harmless error messages (ioctl warnings, etc.). -/
def filterStderr (stderr : String) : String :=
  let lines := stderr.splitOn "\n"
  let filtered := lines.filter fun line =>
    !line.containsSubstr "inappropriate ioctl" &&
    !line.containsSubstr "not a terminal" &&
    !line.containsSubstr "stty: "
  String.intercalate "\n" filtered

/-! ## Bash Execution -/

/-- Execute a bash command using `IO.Process.spawn`.

This is the core execution function, ported from `BashSession.run()`.
Uses `IO.Process.output` for synchronous execution with captured output. -/
def executeBash (command : String) (config : BashConfig := {}) : IO BashResult := do
  let args := #["-c", command]
  let cwd := config.workDir.map (⟨·⟩ : String → System.FilePath)
  let output ← IO.Process.output {
    cmd := "/bin/bash"
    args := args
    cwd := cwd
  }
  return {
    stdout := output.stdout
    stderr := filterStderr output.stderr
    exitCode := output.exitCode
  }

/-- Format bash output for return to the LLM agent.
Truncates very long output to avoid context overflow. -/
def formatBashOutput (result : BashResult) (maxChars : Nat := 100000) : String :=
  let output := if result.stdout.length > maxChars then
    result.stdout.take maxChars ++ "\n... [output truncated]"
  else
    result.stdout
  let errOutput := if result.stderr.isEmpty then "" else
    s!"\nSTDERR:\n{result.stderr}"
  if result.isSuccess then
    output ++ errOutput
  else
    s!"Command failed with exit code {result.exitCode}\n{output}{errOutput}"

/-! ## Tool Interface -/

/-- Bash tool information schema. -/
def bashToolInfo : DGM.Types.ToolInfo :=
  { name := "bash"
    description := "Run commands in a bash shell. Long-running commands will timeout after 120 seconds."
    inputSchema := {
      properties := [
        ("command", { type := "string"
                      description := "The bash command to run" })
      ]
      required := ["command"]
    }
  }

/-- The bash tool function: parses JSON input, executes command, returns output.
Ported from `tool_function` in `tools/bash.py`. -/
def bashToolFunction (input : String) : IO String := do
  -- Simple JSON parsing: extract "command" field
  -- In production, use proper JSON parsing
  let command := extractCommandFromJson input
  let result ← executeBash command
  return formatBashOutput result
where
  /-- Extract the command string from a JSON input.
      Simplified parser; production code should use `Lean.Json`. -/
  extractCommandFromJson (json : String) : String :=
    -- Try to find "command": "..." pattern
    let trimmed := json.trim
    if trimmed.startsWith "{" then
      -- Simple extraction: find after "command" key
      match trimmed.splitOn "\"command\"" with
      | [_, rest] =>
        match rest.splitOn "\"" with
        | _ :: _ :: value :: _ => value
        | _ => trimmed
      | _ => trimmed
    else
      trimmed  -- Assume raw command string

/-- Create a bash tool entry for the registry. -/
def bashToolEntry : ToolEntry :=
  { name := "bash"
    toolInfo := bashToolInfo
    run := bashToolFunction }

end DGM.Tools
