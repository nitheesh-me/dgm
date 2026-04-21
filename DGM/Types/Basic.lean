/-!
# DGM.Types.Basic — Core types shared across the DGM system

Defines the fundamental data structures used throughout the Darwin Gödel Machine,
including message types, tool schemas, performance metrics, and metadata.
-/

namespace DGM.Types

/-! ## Message Types — Models LLM conversation history -/

/-- Content block types in LLM messages. -/
inductive ContentBlockType where
  | text
  | toolUse
  | toolResult
  deriving Repr, BEq, Inhabited

/-- A single content block within a message. -/
structure ContentBlock where
  blockType   : ContentBlockType
  text        : Option String := none
  toolName    : Option String := none
  toolInput   : Option String := none  -- JSON string
  toolUseId   : Option String := none
  content     : Option String := none
  deriving Repr, Inhabited

/-- Message role in conversation. -/
inductive Role where
  | user
  | assistant
  | system
  deriving Repr, BEq, Inhabited

/-- A message in the conversation history. -/
structure Message where
  role    : Role
  blocks  : List ContentBlock
  deriving Repr, Inhabited

/-- Conversation history. -/
abbrev MsgHistory := List Message

/-! ## Tool Schema Types -/

/-- A property in a tool's input schema. -/
structure SchemaProperty where
  type        : String
  description : String
  enumValues  : Option (List String) := none
  deriving Repr, Inhabited

/-- Tool input schema (JSON Schema subset). -/
structure ToolInputSchema where
  type       : String := "object"
  properties : List (String × SchemaProperty)
  required   : List String
  deriving Repr, Inhabited

/-- Tool information (name, description, input schema). -/
structure ToolInfo where
  name        : String
  description : String
  inputSchema : ToolInputSchema
  deriving Repr, Inhabited

/-! ## Performance & Evaluation Types -/

/-- Test case status from log parsing. -/
inductive TestStatus where
  | passed
  | failed
  | skipped
  | error
  | xfail
  deriving Repr, BEq, Inhabited

/-- Individual test result. -/
structure TestResult where
  testCase : String
  status   : TestStatus
  deriving Repr, Inhabited

/-- Aggregated test report: maps test case names to statuses. -/
abbrev TestReport := List (String × TestStatus)

/-- Overall performance metrics for an agent run. -/
structure OverallPerformance where
  accuracyScore          : Float
  totalResolvedInstances : Nat
  totalSubmittedInstances : Nat
  totalUnresolvedIds     : List String
  totalResolvedIds       : List String
  totalEmptyPatchIds     : List String
  deriving Repr, Inhabited

/-- Metadata for a single self-improvement run. -/
structure RunMetadata where
  runId              : String
  parentCommit       : String
  entry              : String
  problemStatement   : String
  modelPatchExists   : Bool
  modelPatchNotEmpty : Bool
  sweDnames          : List String
  overallPerformance : OverallPerformance
  isCompiled         : Bool
  improvementDiagnosis : Option String := none  -- JSON string
  deriving Repr, Inhabited

/-! ## DGM State Types -/

/-- Selection method for choosing parents in evolution. -/
inductive SelectionMethod where
  | random
  | scoreProp
  | scoreChildProp
  | best
  deriving Repr, BEq, Inhabited

/-- State of a single generation in the DGM outer loop. -/
structure GenerationState where
  generation         : Nat
  archive            : List String  -- commit IDs
  selfImproveEntries : List (String × String)  -- (parent_commit, entry)
  children           : List String
  childrenCompiled   : List String
  deriving Repr, Inhabited

/-! ## Language Types (Polyglot) -/

/-- Supported programming languages for the polyglot benchmark. -/
inductive Language where
  | python
  | rust
  | go
  | javascript
  | cpp
  | java
  deriving Repr, BEq, Inhabited

/-- Get the string name of a language. -/
def Language.toString : Language → String
  | .python     => "python"
  | .rust       => "rust"
  | .go         => "go"
  | .javascript => "javascript"
  | .cpp        => "cpp"
  | .java       => "java"

instance : ToString Language := ⟨Language.toString⟩

/-! ## LLM Model Types -/

/-- Supported LLM providers. -/
inductive LLMProvider where
  | anthropic
  | openai
  | bedrock
  | vertexAI
  | deepseek
  deriving Repr, BEq, Inhabited

/-- Get the string name of an LLM provider. -/
def LLMProvider.toString : LLMProvider → String
  | .anthropic => "anthropic"
  | .openai    => "openai"
  | .bedrock   => "bedrock"
  | .vertexAI  => "vertexAI"
  | .deepseek  => "deepseek"

instance : ToString LLMProvider := ⟨LLMProvider.toString⟩

/-- LLM model configuration. -/
structure LLMModel where
  provider    : LLMProvider
  modelName   : String
  maxTokens   : Nat := 4096
  temperature : Float := 1.0
  deriving Repr, Inhabited

end DGM.Types

/-! ## String Utility Extensions -/

/-- Check if a string contains a given substring.
Uses `splitOn` internally: if splitting produces more than one part, the substring is present. -/
def String.containsSubstr (s sub : String) : Bool :=
  (s.splitOn sub).length > 1
