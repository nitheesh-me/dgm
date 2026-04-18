/-!
# DGM.Agent.LLM — LLM Client Abstraction

Low-level LLM API handling with retry logic and multi-provider support.
Ported from: `llm.py` and `llm_withtools.py`
-/

import DGM.Types.Basic
import DGM.Tools.Tool

namespace DGM.Agent

open DGM.Types
open DGM.Tools

/-! ## Constants -/

/-- Maximum output tokens for LLM responses. -/
def maxOutputTokens : Nat := 4096

/-- Default Claude model for tool-using agent. -/
def defaultClaudeModel : String := "bedrock/us.anthropic.claude-3-5-sonnet-20241022-v2:0"

/-- Default OpenAI model for self-improvement. -/
def defaultOpenAIModel : String := "o3-mini-2025-01-31"

/-! ## LLM Client -/

/-- LLM client configuration. -/
structure LLMClientConfig where
  /-- Model identifier string. -/
  modelName  : String
  /-- Provider type. -/
  provider   : LLMProvider
  /-- API key (loaded from environment). -/
  apiKey     : Option String := none
  /-- API endpoint override. -/
  endpoint   : Option String := none
  /-- Temperature for sampling. -/
  temperature : Float := 1.0
  deriving Repr, Inhabited

/-- An LLM client capable of making API calls. -/
structure LLMClient where
  config : LLMClientConfig

/-- Determine the provider from the model name string. -/
def inferProvider (modelName : String) : LLMProvider :=
  if modelName.containsSubstr "claude" || modelName.containsSubstr "anthropic" then
    .anthropic
  else if modelName.containsSubstr "bedrock" then
    .bedrock
  else if modelName.containsSubstr "vertex" then
    .vertexAI
  else if modelName.containsSubstr "deepseek" then
    .deepseek
  else
    .openai

/-- Create an LLM client for the given model.
Ported from `create_client` in `llm.py`. -/
def createClient (modelName : String) : IO LLMClient := do
  let provider := inferProvider modelName
  let apiKey ← match provider with
    | .anthropic => IO.getEnv "ANTHROPIC_API_KEY"
    | .openai    => IO.getEnv "OPENAI_API_KEY"
    | .deepseek  => IO.getEnv "DEEPSEEK_API_KEY"
    | .bedrock   => pure none  -- Uses AWS credentials
    | .vertexAI  => pure none  -- Uses GCP credentials
  return { config := {
    modelName := modelName
    provider := provider
    apiKey := apiKey
  }}

/-! ## LLM Response Types -/

/-- A raw LLM response. -/
structure LLMRawResponse where
  /-- The text content of the response. -/
  content : String
  /-- Stop reason (e.g., "end_turn", "tool_use", "max_tokens"). -/
  stopReason : String
  /-- Tool use blocks (if any). -/
  toolUseBlocks : List ToolUseBlock := []
  deriving Repr, Inhabited

/-- A tool use block from the LLM response. -/
structure ToolUseBlock where
  /-- Tool use ID. -/
  id : String
  /-- Name of the tool to call. -/
  name : String
  /-- Input to the tool (JSON string). -/
  input : String
  deriving Repr, Inhabited

/-! ## API Call Interface -/

/-- Make a single LLM API call.

In practice, this shells out to `curl` or uses FFI.
This is a placeholder that defines the interface. -/
def callLLM (client : LLMClient) (messages : List Message)
    (systemMessage : String) (tools : List ToolInfo := [])
    : IO LLMRawResponse := do
  -- Build the request payload
  let _payload := buildRequestPayload client messages systemMessage tools
  -- In production: HTTP call via IO.Process or FFI
  -- For now, return a placeholder
  return { content := "", stopReason := "end_turn" }
where
  buildRequestPayload (_client : LLMClient) (_messages : List Message)
      (_system : String) (_tools : List ToolInfo) : String :=
    "{}"  -- JSON payload construction

/-- Make an LLM call with exponential backoff retry.
Ported from `get_response_from_llm` in `llm.py`. -/
def callLLMWithRetry (client : LLMClient) (messages : List Message)
    (systemMessage : String) (tools : List ToolInfo := [])
    (maxRetries : Nat := 10) : IO LLMRawResponse := do
  let mut lastError := ""
  for _ in List.range maxRetries do
    try
      let response ← callLLM client messages systemMessage tools
      return response
    catch e =>
      lastError := toString e
      -- Exponential backoff would go here
      IO.sleep 1000
  throw <| IO.userError s!"LLM call failed after {maxRetries} retries: {lastError}"

/-! ## Tool Use Protocol -/

/-- Check if an LLM response contains a tool use request.
Ported from `check_for_tool_use` in `llm_withtools.py`. -/
def checkForToolUse (response : LLMRawResponse) : Option ToolUseBlock :=
  match response.toolUseBlocks with
  | block :: _ => some block
  | []         =>
    -- Check for manual <tool_use> XML tags in content
    if response.content.containsSubstr "<tool_use>" then
      parseManualToolUse response.content
    else
      none
where
  /-- Parse manual tool use from XML tags. -/
  parseManualToolUse (content : String) : Option ToolUseBlock :=
    -- Extract between <tool_use> and </tool_use>
    match content.splitOn "<tool_use>" with
    | [_, rest] =>
      match rest.splitOn "</tool_use>" with
      | [toolJson, _] => some { id := "manual", name := "unknown", input := toolJson.trim }
      | _ => none
    | _ => none

/-- Process a tool call: execute the tool and return the result.
Ported from `process_tool_call` in `llm_withtools.py`. -/
def processToolCall (registry : ToolRegistry) (block : ToolUseBlock)
    : IO String := do
  registry.processCall block.name block.input

/-! ## Agentic Chat Loop -/

/-- State of the agentic chat loop. -/
structure ChatState where
  /-- Current message history. -/
  messages : MsgHistory
  /-- Whether the agent is done. -/
  done : Bool := false
  /-- Number of tool calls made. -/
  toolCallCount : Nat := 0

/-- Maximum number of tool calls in a single chat session. -/
def maxToolCalls : Nat := 200

/-- Run the agentic chat loop.

This is the core agent loop ported from `chat_with_agent` in `llm_withtools.py`:
1. Call LLM with available tools
2. If tool use → execute tool → append result → loop
3. If no tool use → done

Returns the final message history. -/
def chatWithAgent (client : LLMClient) (instruction : String)
    (systemMessage : String) (registry : ToolRegistry)
    (initialHistory : MsgHistory := []) : IO MsgHistory := do
  let userMsg : Message := {
    role := .user
    blocks := [{ blockType := .text, text := some instruction }]
  }
  let mut state : ChatState := {
    messages := initialHistory ++ [userMsg]
    done := false
  }

  while !state.done && state.toolCallCount < maxToolCalls do
    let response ← callLLMWithRetry client state.messages systemMessage
      (registry.allInfos)
    let assistantMsg : Message := {
      role := .assistant
      blocks := [{ blockType := .text, text := some response.content }]
    }
    state := { state with messages := state.messages ++ [assistantMsg] }

    match checkForToolUse response with
    | some toolBlock =>
      let result ← processToolCall registry toolBlock
      let toolResultMsg : Message := {
        role := .user
        blocks := [{ blockType := .toolResult
                     content := some result
                     toolUseId := some toolBlock.id }]
      }
      state := { state with
        messages := state.messages ++ [toolResultMsg]
        toolCallCount := state.toolCallCount + 1
      }
    | none =>
      state := { state with done := true }

  return state.messages

/-! ## JSON Extraction -/

/-- Extract JSON between markdown code block markers.
Ported from `extract_json_between_markers` in `llm.py`. -/
def extractJsonBetweenMarkers (text : String) : Option String :=
  let markers := ["```json", "```"]
  match text.splitOn (markers.get! 0) with
  | [_, rest] =>
    match rest.splitOn (markers.get! 1) with
    | jsonStr :: _ => some jsonStr.trim
    | _ => none
  | _ => none

end DGM.Agent
