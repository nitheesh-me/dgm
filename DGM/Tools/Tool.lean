/-!
# DGM.Tools.Tool — Tool Typeclass and Registry

Defines the `Tool` typeclass that all DGM tools must implement,
and the tool registry for dynamic tool loading.

Ported from: `tools/__init__.py`
-/

namespace DGM.Tools

open DGM.Types

/-! ## Tool Typeclass -/

/-- The Tool typeclass. Every tool must provide:
- `info`: The tool's schema (name, description, input schema)
- `execute`: The tool's execution function -/
class Tool (α : Type) where
  /-- Get the tool's information schema. -/
  info : α → ToolInfo
  /-- Execute the tool with the given JSON input string.
      Returns the tool's output as a string. -/
  execute : α → String → IO String

/-! ## Tool Entry -/

/-- A concrete tool entry in the registry. Uses existential to erase the type. -/
structure ToolEntry where
  /-- Tool name. -/
  name : String
  /-- Tool schema information. -/
  toolInfo : ToolInfo
  /-- Execute the tool. -/
  run : String → IO String

/-! ## Tool Registry -/

/-- The tool registry holds all available tools. -/
structure ToolRegistry where
  tools : List ToolEntry
  deriving Inhabited

/-- Create an empty tool registry. -/
def ToolRegistry.empty : ToolRegistry := { tools := [] }

/-- Register a tool in the registry. -/
def ToolRegistry.register (reg : ToolRegistry) (entry : ToolEntry) : ToolRegistry :=
  { tools := entry :: reg.tools }

/-- Look up a tool by name. -/
def ToolRegistry.lookup (reg : ToolRegistry) (name : String) : Option ToolEntry :=
  reg.tools.find? (·.name == name)

/-- Get all tool infos for passing to the LLM. -/
def ToolRegistry.allInfos (reg : ToolRegistry) : List ToolInfo :=
  reg.tools.map (·.toolInfo)

/-- Process a tool call: look up the tool and execute it. -/
def ToolRegistry.processCall (reg : ToolRegistry) (toolName : String) (toolInput : String)
    : IO String := do
  match reg.lookup toolName with
  | some entry => entry.run toolInput
  | none       => return s!"Error: Unknown tool '{toolName}'"

/-! ## Load All Tools -/

/-- Load all tools and return a populated registry.
    This is the Lean equivalent of `load_all_tools()`. -/
def loadAllTools : IO ToolRegistry := do
  -- Tools are registered statically (unlike Python's dynamic loading)
  -- The actual Bash and Edit tool instances will be registered by the caller
  return ToolRegistry.empty

end DGM.Tools
