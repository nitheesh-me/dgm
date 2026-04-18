import DGM.Types.Basic
import DGM.Tools.Tool
import DGM.Agent.MockLLM

/-!
# DGM.Agent.LLM — LLM Client Abstraction

Low-level LLM API handling with retry logic and multi-provider support.
Calls real APIs via `curl` shell-out (IO.Process).
Ported from: `llm.py` and `llm_withtools.py`
-/
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
  /-- AWS region for Bedrock. -/
  awsRegion  : Option String := none
  /-- Whether to use mock responses (no API key available). -/
  useMock    : Bool := false
  deriving Repr, Inhabited

/-- An LLM client capable of making API calls. -/
structure LLMClient where
  config : LLMClientConfig

/-- Determine the provider from the model name string. -/
def inferProvider (modelName : String) : LLMProvider :=
  if modelName.containsSubstr "bedrock" then
    .bedrock
  else if modelName.containsSubstr "vertex" then
    .vertexAI
  else if modelName.containsSubstr "claude" || modelName.containsSubstr "anthropic" then
    .anthropic
  else if modelName.containsSubstr "deepseek" then
    .deepseek
  else
    .openai

/-- Create an LLM client for the given model.
Ported from `create_client` in `llm.py`.
When API keys are missing, automatically enables mock mode. -/
def createClient (modelName : String) : IO LLMClient := do
  let provider := inferProvider modelName
  let apiKey ← match provider with
    | .anthropic => IO.getEnv "ANTHROPIC_API_KEY"
    | .openai    => IO.getEnv "OPENAI_API_KEY"
    | .deepseek  => IO.getEnv "DEEPSEEK_API_KEY"
    | .bedrock   => pure none  -- Uses AWS credentials
    | .vertexAI  => pure none  -- Uses GCP credentials
  let awsRegion ← match provider with
    | .bedrock => IO.getEnv "AWS_REGION_NAME"
    | _        => pure none
  -- Determine if mock mode is needed
  let useMock ← MockLLM.shouldUseMock
  let needsKey := match provider with
    | .bedrock | .vertexAI => false
    | _ => true
  let useMock := useMock || (needsKey && apiKey.isNone)
  if useMock then
    IO.eprintln s!"[LLM] Mock mode: no API key for {provider}, using pre-selected responses"
  else
    IO.println s!"[LLM] Using {provider} with model {modelName}"
  return { config := {
    modelName := modelName
    provider := provider
    apiKey := apiKey
    awsRegion := awsRegion
    useMock := useMock
  }}

/-! ## LLM Response Types -/

/-- A tool use block from the LLM response. -/
structure ToolUseBlock where
  /-- Tool use ID. -/
  id : String
  /-- Name of the tool to call. -/
  name : String
  /-- Input to the tool (JSON string). -/
  input : String
  deriving Repr, Inhabited

/-- A raw LLM response. -/
structure LLMRawResponse where
  /-- The text content of the response. -/
  content : String
  /-- Stop reason (e.g., "end_turn", "tool_use", "max_tokens"). -/
  stopReason : String
  /-- Tool use blocks (if any). -/
  toolUseBlocks : List ToolUseBlock := []
  deriving Repr, Inhabited

/-! ## JSON Helpers -/

/-- Escape a string for inclusion in a JSON string literal. -/
def jsonEscape (s : String) : String :=
  s.foldl (fun acc c =>
    match c with
    | '\\' => acc ++ "\\\\"
    | '"'  => acc ++ "\\\""
    | '\n' => acc ++ "\\n"
    | '\t' => acc ++ "\\t"
    | '\r' => acc ++ "\\r"
    | c    =>
      if c.toNat < 32 then acc  -- Skip other control characters
      else acc.push c
  ) ""

/-- Build a JSON array of message objects from message history. -/
def buildMessagesJson (messages : List Message) : String :=
  let msgJsons := messages.map fun msg =>
    let roleStr := match msg.role with
      | .user      => "user"
      | .assistant => "assistant"
      | .system    => "system"
    let content := msg.blocks.filterMap (fun b => b.text) |> String.intercalate "\n"
    s!"\{\"role\": \"{roleStr}\", \"content\": \"{jsonEscape content}\"}"
  "[" ++ String.intercalate ", " msgJsons ++ "]"

/-- Build a JSON array of tool definitions in Anthropic/Claude format. -/
def buildToolsJsonClaude (tools : List ToolInfo) : String :=
  let toolJsons := tools.map fun tool =>
    let propsJson := tool.inputSchema.properties.map fun (name, prop) =>
      s!"\"{name}\": \{\"type\": \"{prop.type}\", \"description\": \"{jsonEscape prop.description}\"}"
    let requiredJson := tool.inputSchema.required.map fun r => s!"\"{r}\""
    s!"\{\"name\": \"{tool.name}\", \"description\": \"{jsonEscape tool.description}\", " ++
    s!"\"input_schema\": \{\"type\": \"object\", " ++
    s!"\"properties\": \{{String.intercalate ", " propsJson}}, " ++
    s!"\"required\": [{String.intercalate ", " requiredJson}]}}"
  "[" ++ String.intercalate ", " toolJsons ++ "]"

/-- Build a JSON array of tool definitions in OpenAI format. -/
def buildToolsJsonOpenAI (tools : List ToolInfo) : String :=
  let toolJsons := tools.map fun tool =>
    let propsJson := tool.inputSchema.properties.map fun (name, prop) =>
      s!"\"{name}\": \{\"type\": \"{prop.type}\", \"description\": \"{jsonEscape prop.description}\"}"
    let requiredJson := tool.inputSchema.required.map fun r => s!"\"{r}\""
    s!"\{\"type\": \"function\", \"name\": \"{tool.name}\", \"description\": \"{jsonEscape tool.description}\", " ++
    s!"\"parameters\": \{\"type\": \"object\", " ++
    s!"\"properties\": \{{String.intercalate ", " propsJson}}, " ++
    s!"\"required\": [{String.intercalate ", " requiredJson}], " ++
    s!"\"additionalProperties\": false}, \"strict\": true}"
  "[" ++ String.intercalate ", " toolJsons ++ "]"

/-! ## API Call Interface — Real Implementation via curl -/

/-- Build the full API request body for Anthropic/Claude. -/
def buildAnthropicPayload (client : LLMClient) (messages : List Message)
    (systemMessage : String) (tools : List ToolInfo) : String :=
  let model := match client.config.provider with
    | .bedrock => client.config.modelName.splitOn "/" |>.getLast?.getD client.config.modelName
    | _        => client.config.modelName
  let messagesJson := buildMessagesJson messages
  let toolsSection := if tools.isEmpty then ""
    else s!", \"tools\": {buildToolsJsonClaude tools}, \"tool_choice\": \{\"type\": \"auto\"}"
  s!"\{\"model\": \"{model}\", \"max_tokens\": {maxOutputTokens}, " ++
  s!"\"system\": \"{jsonEscape systemMessage}\", " ++
  s!"\"messages\": {messagesJson}{toolsSection}}"

/-- Build the full API request body for OpenAI. -/
def buildOpenAIPayload (client : LLMClient) (messages : List Message)
    (systemMessage : String) (tools : List ToolInfo) : String :=
  let sysBlock : ContentBlock := { blockType := .text, text := some systemMessage }
  let sysMsg : Message := { role := Role.system, blocks := [sysBlock] }
  let allMessages := [sysMsg] ++ messages
  let model := client.config.modelName
  let isO1O3 := model.startsWith "o1-" || model.startsWith "o3-"
  let messagesJson := buildMessagesJson allMessages
  let tempSection := if isO1O3 then "" else s!", \"temperature\": {client.config.temperature}"
  let toolsSection := if tools.isEmpty then ""
    else s!", \"tools\": {buildToolsJsonOpenAI tools}, \"tool_choice\": \"auto\""
  s!"\{\"model\": \"{model}\", \"messages\": {messagesJson}" ++
  s!"{tempSection}, \"max_tokens\": {maxOutputTokens}{toolsSection}}"

/-- Parse the text content from an Anthropic response JSON string. -/
def parseAnthropicResponse (responseBody : String) : IO LLMRawResponse := do
  -- Extract stop_reason
  let stopReason := extractField responseBody "stop_reason"
  -- Extract text content blocks
  let content := extractContentBlocks responseBody
  -- Extract tool_use blocks
  let toolBlocks := extractToolUseBlocks responseBody
  return { content := content, stopReason := stopReason, toolUseBlocks := toolBlocks }
where
  extractField (json field : String) : String :=
    match json.splitOn s!"\"{field}\": \"" with
    | [_, rest] =>
      match rest.splitOn "\"" with
      | val :: _ => val
      | _ => ""
    | _ => ""
  extractContentBlocks (json : String) : String :=
    -- Find text blocks in content array
    let parts := json.splitOn "\"text\": \""
    if parts.length > 1 then
      match parts with
      | _ :: rest :: _ =>
        -- Find the closing quote (handling escaped quotes)
        let chars := rest.toList
        let result := extractUntilUnescapedQuote chars ""
        result
      | _ => ""
    else ""
  extractUntilUnescapedQuote : List Char → String → String
    | [], acc => acc
    | '\\' :: '"' :: rest, acc => extractUntilUnescapedQuote rest (acc ++ "\"")
    | '\\' :: 'n' :: rest, acc => extractUntilUnescapedQuote rest (acc ++ "\n")
    | '\\' :: 't' :: rest, acc => extractUntilUnescapedQuote rest (acc ++ "\t")
    | '\\' :: '\\' :: rest, acc => extractUntilUnescapedQuote rest (acc ++ "\\")
    | '"' :: _, acc => acc
    | c :: rest, acc => extractUntilUnescapedQuote rest (acc.push c)
  extractToolUseBlocks (json : String) : List ToolUseBlock :=
    -- Find tool_use type blocks
    let parts := json.splitOn "\"type\": \"tool_use\""
    if parts.length <= 1 then []
    else
      parts.tail.filterMap fun block =>
        let idVal := extractField block "id"
        let nameVal := extractField block "name"
        -- Extract input as a JSON object
        match block.splitOn "\"input\": " with
        | [_, rest] =>
          -- Find matching closing brace
          let inputJson := extractJsonObject rest
          some { id := idVal, name := nameVal, input := inputJson }
        | _ => none
  extractJsonObject (s : String) : String :=
    let chars := s.toList
    extractJsonObjectGo chars 0 ""
  extractJsonObjectGo : List Char → Nat → String → String
    | [], _, acc => acc
    | '{' :: rest, depth, acc => extractJsonObjectGo rest (depth + 1) (acc.push '{')
    | '}' :: rest, depth, acc =>
      if depth == 1 then acc.push '}'
      else extractJsonObjectGo rest (depth - 1) (acc.push '}')
    | c :: rest, depth, acc =>
      if depth == 0 && c != '{' then extractJsonObjectGo rest depth acc
      else extractJsonObjectGo rest depth (acc.push c)

/-- Parse the text content from an OpenAI response JSON string. -/
def parseOpenAIResponse (responseBody : String) : IO LLMRawResponse := do
  -- Extract content from choices[0].message.content
  let content := match responseBody.splitOn "\"content\": \"" with
    | [_, rest] =>
      match rest.splitOn "\"" with
      | val :: _ => val.replace "\\n" "\n" |>.replace "\\t" "\t" |>.replace "\\\"" "\""
      | _ => ""
    | _ =>
      -- Try null content (tool calls)
      ""
  -- Extract finish_reason
  let stopReason := match responseBody.splitOn "\"finish_reason\": \"" with
    | [_, rest] =>
      match rest.splitOn "\"" with
      | val :: _ => val
      | _ => "stop"
    | _ => "stop"
  -- Extract tool_calls if present
  let toolBlocks := if responseBody.containsSubstr "\"tool_calls\"" then
    parseOpenAIToolCalls responseBody
  else []
  return { content := content, stopReason := stopReason, toolUseBlocks := toolBlocks }
where
  parseOpenAIToolCalls (json : String) : List ToolUseBlock :=
    match json.splitOn "\"tool_calls\":" with
    | [_, rest] =>
      -- Extract function call info
      let idVal := match rest.splitOn "\"id\": \"" with
        | [_, r] =>
          match r.splitOn "\"" with
          | v :: _ => v
          | _ => ""
        | _ => ""
      let nameVal := match rest.splitOn "\"name\": \"" with
        | [_, r] =>
          match r.splitOn "\"" with
          | v :: _ => v
          | _ => ""
        | _ => ""
      let argsVal := match rest.splitOn "\"arguments\": \"" with
        | [_, r] =>
          match r.splitOn "\"" with
          | v :: _ => v.replace "\\\"" "\""
          | _ => "{}"
        | _ => "{}"
      if nameVal.isEmpty then []
      else [{ id := idVal, name := nameVal, input := argsVal }]
    | _ => []

/-- Make a single LLM API call via curl, or return mock response if in mock mode.
Shells out to `curl` with the appropriate headers and payload.
When `client.config.useMock` is true, returns pre-selected probabilistic responses. -/
def callLLM (client : LLMClient) (messages : List Message)
    (systemMessage : String) (tools : List ToolInfo := [])
    : IO LLMRawResponse := do
  -- Mock mode: return pre-selected response
  if client.config.useMock then
    let (content, stopReason, _toolCalls) ← MockLLM.mockLLMCall messages systemMessage tools
    return { content := content, stopReason := stopReason, toolUseBlocks := [] }
  -- Real API call
  match client.config.provider with
  | .anthropic | .bedrock | .vertexAI =>
    callAnthropic client messages systemMessage tools
  | .openai | .deepseek =>
    callOpenAI client messages systemMessage tools
where
  callAnthropic (client : LLMClient) (messages : List Message)
      (systemMessage : String) (tools : List ToolInfo) : IO LLMRawResponse := do
    let payload := buildAnthropicPayload client messages systemMessage tools
    let apiKey := client.config.apiKey.getD ""
    let apiUrl := match client.config.provider with
      | .bedrock =>
        let region := client.config.awsRegion.getD "us-east-1"
        let model := client.config.modelName.splitOn "/" |>.getLast?.getD client.config.modelName
        s!"https://bedrock-runtime.{region}.amazonaws.com/model/{model}/invoke"
      | _ => client.config.endpoint.getD "https://api.anthropic.com/v1/messages"
    -- Write payload to temp file to avoid shell escaping issues
    let tmpFile := s!"/tmp/dgm_llm_req_{← IO.monoNanosNow}.json"
    IO.FS.writeFile ⟨tmpFile⟩ payload
    let args := match client.config.provider with
      | .bedrock =>
        -- Bedrock uses AWS Signature V4 — use Python helper or aws cli
        #["-s", "-X", "POST", apiUrl,
          "-H", "Content-Type: application/json",
          "-d", s!"@{tmpFile}",
          "--max-time", "120"]
      | _ =>
        #["-s", "-X", "POST", apiUrl,
          "-H", s!"x-api-key: {apiKey}",
          "-H", "anthropic-version: 2023-06-01",
          "-H", "Content-Type: application/json",
          "-d", s!"@{tmpFile}",
          "--max-time", "120"]
    let result ← IO.Process.output { cmd := "curl", args := args }
    IO.FS.removeFile ⟨tmpFile⟩
    if result.exitCode != 0 then
      throw <| IO.userError s!"curl failed (exit {result.exitCode}): {result.stderr}"
    parseAnthropicResponse result.stdout

  callOpenAI (client : LLMClient) (messages : List Message)
      (systemMessage : String) (tools : List ToolInfo) : IO LLMRawResponse := do
    let payload := buildOpenAIPayload client messages systemMessage tools
    let apiKey := client.config.apiKey.getD ""
    let apiUrl := match client.config.provider with
      | .deepseek => "https://api.deepseek.com/v1/chat/completions"
      | _         => client.config.endpoint.getD "https://api.openai.com/v1/chat/completions"
    let tmpFile := s!"/tmp/dgm_llm_req_{← IO.monoNanosNow}.json"
    IO.FS.writeFile ⟨tmpFile⟩ payload
    let result ← IO.Process.output {
      cmd := "curl"
      args := #["-s", "-X", "POST", apiUrl,
        "-H", s!"Authorization: Bearer {apiKey}",
        "-H", "Content-Type: application/json",
        "-d", s!"@{tmpFile}",
        "--max-time", "120"]
    }
    IO.FS.removeFile ⟨tmpFile⟩
    if result.exitCode != 0 then
      throw <| IO.userError s!"curl failed (exit {result.exitCode}): {result.stderr}"
    parseOpenAIResponse result.stdout

/-- Make an LLM call with exponential backoff retry.
Ported from `get_response_from_llm` in `llm.py`. -/
def callLLMWithRetry (client : LLMClient) (messages : List Message)
    (systemMessage : String) (tools : List ToolInfo := [])
    (maxRetries : Nat := 10) : IO LLMRawResponse := do
  let mut lastError := ""
  let mut delay : UInt32 := 1000  -- Start with 1 second
  for i in List.range maxRetries do
    try
      let response ← callLLM client messages systemMessage tools
      if response.content.isEmpty && response.toolUseBlocks.isEmpty then
        throw <| IO.userError "Empty response from LLM"
      return response
    catch e =>
      lastError := toString e
      IO.eprintln s!"[LLM] Attempt {i + 1}/{maxRetries} failed: {lastError}"
      IO.sleep delay
      delay := min (delay * 2) 60000  -- Cap at 60 seconds
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
  IO.println s!"[Tool] Executing: {block.name}"
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
    (initialHistory : MsgHistory := [])
    (logging : String → IO Unit := IO.println) : IO MsgHistory := do
  let userMsg : Message := {
    role := .user
    blocks := [{ blockType := .text, text := some instruction }]
  }
  let mut state : ChatState := {
    messages := initialHistory ++ [userMsg]
    done := false
  }
  logging s!"[Agent] Starting chat loop with instruction ({instruction.length} chars)"

  while !state.done && state.toolCallCount < maxToolCalls do
    let response ← callLLMWithRetry client state.messages systemMessage
      (registry.allInfos)
    let assistantMsg : Message := {
      role := .assistant
      blocks := [{ blockType := .text, text := some response.content }]
    }
    state := { state with messages := state.messages ++ [assistantMsg] }
    logging s!"[Agent] Response ({response.content.length} chars), stop={response.stopReason}"

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
      logging s!"[Agent] Tool call #{state.toolCallCount}: {toolBlock.name}"
    | none =>
      state := { state with done := true }
      logging s!"[Agent] Done after {state.toolCallCount} tool calls"

  return state.messages

/-! ## JSON Extraction -/

/-- Extract JSON between markdown code block markers.
Ported from `extract_json_between_markers` in `llm.py`. -/
def extractJsonBetweenMarkers (text : String) : Option String :=
  -- Try ```json ... ``` first
  match text.splitOn "```json" with
  | [_, rest] =>
    match rest.splitOn "```" with
    | jsonStr :: _ => some jsonStr.trim
    | _ => none
  | _ =>
    -- Fallback: find first { ... } in text
    match text.splitOn "{" with
    | _ :: rest =>
      let joined := "{" ++ String.intercalate "{" rest
      match joined.splitOn "}" with
      | parts =>
        if parts.length > 1 then
          some (String.intercalate "}" (parts.take (parts.length - 1)) ++ "}")
        else none
    | _ => none

end DGM.Agent
