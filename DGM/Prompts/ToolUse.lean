/-!
# DGM.Prompts.ToolUse — Tool Usage Prompt Format

Provides tool usage format instructions for LLMs without native tool calling.
Ported from: `prompts/tooluse_prompt.py`
-/

import DGM.Tools.Tool

namespace DGM.Prompts.ToolUse

open DGM.Tools

/-- Generate tool usage instructions from the tool registry.
Ported from `get_tooluse_prompt` in `prompts/tooluse_prompt.py`.

For LLMs that don't support native tool calling (e.g., DeepSeek, Llama),
this prompt teaches them the XML-based tool calling format. -/
def getToolUsePrompt (registry : ToolRegistry) : String :=
  let toolDescriptions := registry.tools.map fun entry =>
    let props := entry.toolInfo.inputSchema.properties.map fun (name, prop) =>
      s!"    - {name} ({prop.type}): {prop.description}"
    let required := entry.toolInfo.inputSchema.required
    s!"### {entry.name}\n{entry.toolInfo.description}\n\nParameters:\n" ++
    String.intercalate "\n" props ++
    s!"\nRequired: {required}\n"

  "## Available Tools\n\n" ++
  String.intercalate "\n" toolDescriptions ++
  "\n## Tool Usage Format\n\n" ++
  "To use a tool, wrap your call in <tool_use> tags:\n\n" ++
  "```\n<tool_use>\n{\"tool_name\": \"tool_name_here\", \"tool_input\": {\"param\": \"value\"}}\n</tool_use>\n```\n\n" ++
  "Wait for the tool result before continuing. " ++
  "You can use multiple tools in sequence to accomplish your task."

end DGM.Prompts.ToolUse
