/-!
# DGM.Utils.Common — Common File I/O Utilities

Ported from: `utils/common_utils.py`
-/

namespace DGM.Utils.Common

/-- Read a file and strip leading/trailing whitespace.
Ported from `read_file` in `utils/common_utils.py`. -/
def readFile (filePath : String) : IO String := do
  let content ← IO.FS.readFile ⟨filePath⟩
  return content.trimAscii.toString

/-- Load and parse a JSON file.
Ported from `load_json_file` in `utils/common_utils.py`.
Returns the raw JSON string (proper parsing requires Lean.Json). -/
def loadJsonFile (filePath : String) : IO String := do
  IO.FS.readFile ⟨filePath⟩

/-- Write a string to a file, creating parent directories if needed. -/
def writeFile (filePath content : String) : IO Unit := do
  -- Ensure parent directory exists
  let path := System.FilePath.mk filePath
  match path.parent with
  | some parentDir =>
    IO.FS.createDirAll parentDir
  | none => pure ()
  IO.FS.writeFile path content

/-- Check if a file exists. -/
def fileExists (filePath : String) : IO Bool :=
  System.FilePath.pathExists ⟨filePath⟩

/-- Read lines from a file. -/
def readLines (filePath : String) : IO (List String) := do
  let content ← IO.FS.readFile ⟨filePath⟩
  return content.splitOn "\n" |>.filter (·.length > 0)

end DGM.Utils.Common
