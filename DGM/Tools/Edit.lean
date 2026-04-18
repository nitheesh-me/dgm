import DGM.Tools.Tool

/-!
# DGM.Tools.Edit — File Editor Tool

File operations (view, create, edit) with path validation.
Ported from: `tools/edit.py`
-/
namespace DGM.Tools

/-! ## Edit Commands -/

/-- The three editor commands. -/
inductive EditCommand where
  | view
  | create
  | edit
  deriving Repr, BEq, Inhabited

/-- Parse a command string into an EditCommand. -/
def EditCommand.fromString (s : String) : Option EditCommand :=
  match s.toLower with
  | "view"   => some .view
  | "create" => some .create
  | "edit"   => some .edit
  | _        => none

/-! ## Path Validation -/

/-- Validated absolute path. A refinement type ensuring the path is absolute. -/
structure ValidPath where
  path : String
  isAbsolute : path.startsWith "/" = true

/-- Validate that a path is absolute. -/
def validatePath (path : String) (command : EditCommand) : IO ValidPath := do
  if h : path.startsWith "/" then
    return ⟨path, h⟩
  else
    throw <| IO.userError s!"The path {path} is not an absolute path. Please provide an absolute path."

/-! ## File Operations -/

/-- Read a file and return its contents with line numbers. -/
def readFileWithLineNumbers (path : String) : IO String := do
  let content ← IO.FS.readFile ⟨path⟩
  let lines := content.splitOn "\n"
  let mut result : List String := []
  let mut lineNum : Nat := 1
  for line in lines do
    result := result ++ [s!"{lineNum}\t{line}"]
    lineNum := lineNum + 1
  return String.intercalate "\n" result

/-- List directory contents (non-recursive, up to 2 levels). -/
def listDirectory (path : String) : IO String := do
  let entries ← System.FilePath.readDir ⟨path⟩
  let names := entries.toList.map (·.fileName)
  let sorted := names.mergeSort (· < ·)
  return String.intercalate "\n" sorted

/-- View a file or directory. -/
def viewPath (path : String) : IO String := do
  let isDir ← System.FilePath.isDir ⟨path⟩
  if isDir then
    listDirectory path
  else
    readFileWithLineNumbers path

/-- Create a new file with given content. -/
def createFile (path : String) (content : String) : IO String := do
  let pathExists ← System.FilePath.pathExists ⟨path⟩
  if pathExists then
    throw <| IO.userError s!"File already exists at {path}. Use 'edit' to modify it."
  IO.FS.writeFile ⟨path⟩ content
  return s!"File created successfully at {path}"

/-- Edit an existing file by replacing old content with new content. -/
def editFile (path : String) (newContent : String) : IO String := do
  let pathExists ← System.FilePath.pathExists ⟨path⟩
  if !pathExists then
    throw <| IO.userError s!"File does not exist at {path}. Use 'create' to create it."
  IO.FS.writeFile ⟨path⟩ newContent
  return s!"File edited successfully at {path}"

/-! ## Tool Interface -/

/-- Editor tool information schema. -/
def editToolInfo : DGM.Types.ToolInfo :=
  { name := "editor"
    description := "View, create, or edit files. Commands: view (show file/dir), create (new file), edit (modify file)."
    inputSchema := {
      properties := [
        ("command", { type := "string"
                      description := "The editor command: view, create, or edit"
                      enumValues := some ["view", "create", "edit"] }),
        ("path",    { type := "string"
                      description := "Absolute path to the file or directory" }),
        ("file_text", { type := "string"
                        description := "Content for create/edit commands" })
      ]
      required := ["command", "path"]
    }
  }

/-- The editor tool function: parses input, dispatches to operation. -/
def editToolFunction (input : String) : IO String := do
  -- Simplified: in production, parse JSON properly
  -- For now, we extract command, path, and optional file_text
  let (command, path, fileText) := parseEditInput input
  let vpath ← validatePath path (command)
  match command with
  | .view   => viewPath vpath.path
  | .create =>
    match fileText with
    | some text => createFile vpath.path text
    | none => return "Error: file_text is required for create command"
  | .edit =>
    match fileText with
    | some text => editFile vpath.path text
    | none => return "Error: file_text is required for edit command"
where
  /-- Parse the edit tool input (simplified). -/
  parseEditInput (json : String) : EditCommand × String × Option String :=
    -- Placeholder: proper JSON parsing needed
    (.view, json, none)

/-- Create an editor tool entry for the registry. -/
def editToolEntry : ToolEntry :=
  { name := "editor"
    toolInfo := editToolInfo
    run := editToolFunction }

end DGM.Tools
