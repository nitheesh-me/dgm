/-!
# DGM.Prompts.TestRepo — Test Description Prompt Generation

Generates test execution instructions for different benchmark types.
Ported from: `prompts/testrepo_prompt.py`
-/

import DGM.Types.Basic

namespace DGM.Prompts.TestRepo

open DGM.Types

/-- Generate test description for an evaluation instance.
Ported from `get_test_description` in `prompts/testrepo_prompt.py`. -/
def getTestDescription (evalScript : String) (repo : String)
    (polyglot : Bool := false) : String :=
  if polyglot then
    s!"To run the tests for this repository, use the following command:\n```\n{evalScript}\n```"
  else if repo == "dgm" then
    "To run the tests for the DGM agent itself:\n" ++
    "```\npytest -rA tests/test_bash_tool.py tests/test_edit_tool.py\n```\n" ++
    "Note: Only modify files in tools/ and utils/ directories."
  else
    s!"To run the tests:\n```\n{evalScript}\n```"

/-- Get the test command for a specific language.
Ported from language-specific test command lookup. -/
def getTestCommand (lang : Language) : String :=
  match lang with
  | .python     => "pytest -rA --tb=long"
  | .rust       => "cargo test -- --include-ignored"
  | .go         => "go test ./..."
  | .javascript => "npm test"
  | .cpp        => "cmake --build build && ctest --test-dir build"
  | .java       => "./gradlew test"

end DGM.Prompts.TestRepo
