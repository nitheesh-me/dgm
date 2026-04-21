import DGM.Types.Basic

/-!
# DGM.Utils.LogParsers — Test Log Parsing

Parsers for extracting test results from different test framework logs.
Ported from: `utils/swe_log_parsers.py`
-/
namespace DGM.Utils.LogParsers

open DGM.Types

/-! ## Pytest Log Parser -/

/-- Parse pytest output into test results.
Ported from `parse_log_pytest` in `utils/swe_log_parsers.py`. -/
def parseLogPytest (log : String) : List (String × TestStatus) :=
  let lines := log.splitOn "\n"
  lines.filterMap fun line =>
    let trimmed := line.trimAscii.toString
    if trimmed.containsSubstr "PASSED" then
      some (extractTestName trimmed, TestStatus.passed)
    else if trimmed.containsSubstr "FAILED" then
      some (extractTestName trimmed, TestStatus.failed)
    else if trimmed.containsSubstr "SKIPPED" then
      some (extractTestName trimmed, TestStatus.skipped)
    else if trimmed.containsSubstr "ERROR" then
      some (extractTestName trimmed, TestStatus.error)
    else if trimmed.containsSubstr "XFAIL" then
      some (extractTestName trimmed, TestStatus.xfail)
    else
      none
where
  /-- Extract test name from a pytest output line. -/
  extractTestName (line : String) : String :=
    match line.splitOn " " with
    | _ :: name :: _ => name
    | _ => line

/-- Parse pytest output with parametrized test support.
Ported from `parse_log_pytest_options`. -/
def parseLogPytestOptions (log : String) : List (String × TestStatus) :=
  -- Handle parametrized tests: test_name[param1-param2]
  parseLogPytest log

/-- Parse pytest v2 output (later pytest versions with different status format).
Ported from `parse_log_pytest_v2` in `utils/swe_log_parsers.py`.
Used for astropy, scikit-learn, sphinx. -/
def parseLogPytestV2 (log : String) : List (String × TestStatus) :=
  let lines := log.splitOn "\n"
  lines.filterMap fun line =>
    let trimmed := line.trimAscii.toString
    -- Format: "PASSED path/test.py::test_name" or "test_name PASSED"
    if trimmed.startsWith "PASSED " then
      let rest := (trimmed.drop 7).toString.trimAscii.toString
      some (rest.splitOn " " |>.head?.getD rest, TestStatus.passed)
    else if trimmed.startsWith "FAILED " then
      -- Handle "FAILED test_name - reason" → strip the " - reason" suffix
      let rest := (trimmed.drop 7).toString.trimAscii.toString
      let name := (rest.replace " - " " ").splitOn " " |>.head?.getD rest
      some (name, TestStatus.failed)
    else if trimmed.startsWith "ERROR " then
      let rest := (trimmed.drop 6).toString.trimAscii.toString
      some (rest.splitOn " " |>.head?.getD rest, TestStatus.error)
    -- Also handle older "test_name PASSED" format
    else if trimmed.containsSubstr " PASSED" then
      some (trimmed.splitOn " " |>.head?.getD trimmed, TestStatus.passed)
    else if trimmed.containsSubstr " FAILED" then
      some (trimmed.splitOn " " |>.head?.getD trimmed, TestStatus.failed)
    else
      none

/-! ## Django Test Log Parser -/

/-- Parse Django test output.
Ported from `parse_log_django` in `utils/swe_log_parsers.py`. -/
def parseLogDjango (log : String) : List (String × TestStatus) :=
  let lines := log.splitOn "\n"
  lines.filterMap fun line =>
    let trimmed := line.trimAscii.toString
    if trimmed.containsSubstr "... ok" then
      some (trimmed.splitOn " " |>.head?.getD trimmed, TestStatus.passed)
    else if trimmed.containsSubstr "... FAIL" then
      some (trimmed.splitOn " " |>.head?.getD trimmed, TestStatus.failed)
    else if trimmed.containsSubstr "... ERROR" then
      some (trimmed.splitOn " " |>.head?.getD trimmed, TestStatus.error)
    else if trimmed.containsSubstr "... skipped" then
      some (trimmed.splitOn " " |>.head?.getD trimmed, TestStatus.skipped)
    else
      none

/-! ## Seaborn Log Parser -/

/-- Parse seaborn test output.
Ported from `parse_log_seaborn` in `utils/swe_log_parsers.py`. -/
def parseLogSeaborn (log : String) : List (String × TestStatus) :=
  let lines := log.splitOn "\n"
  lines.filterMap fun line =>
    let trimmed := line.trimAscii.toString
    if trimmed.startsWith "FAILED " then
      let name := (trimmed.drop 7).toString.trimAscii.toString.splitOn " " |>.head?.getD trimmed
      some (name, TestStatus.failed)
    else if trimmed.containsSubstr " PASSED " then
      let parts := trimmed.splitOn " "
      match parts with
      | name :: st :: _ => if st == "PASSED" then some (name, TestStatus.passed) else none
      | _ => none
    else if trimmed.startsWith "PASSED " then
      let parts := (trimmed.drop 7).toString.trimAscii.toString.splitOn " "
      some (parts.head?.getD trimmed, TestStatus.passed)
    else
      none

/-! ## Sympy Log Parser -/

/-- Parse Sympy test output.
Ported from `parse_log_sympy` in `utils/swe_log_parsers.py`. -/
def parseLogSympy (log : String) : List (String × TestStatus) :=
  let lines := log.splitOn "\n"
  lines.filterMap fun line =>
    let trimmed := line.trimAscii.toString
    -- Handle "test_name E" or "test_name F" or "test_name ok" patterns
    if trimmed.startsWith "test_" then
      -- Strip trailing [FAIL] or [OK] markers
      let stripped := if trimmed.containsSubstr "[FAIL]" || trimmed.containsSubstr "[OK]" then
        let idx := trimmed.splitOn "[" |>.head?.getD trimmed
        idx.trimAscii.toString
      else trimmed
      if stripped.containsSubstr " E" then
        let testName := stripped.splitOn " " |>.head?.getD stripped
        some (testName, TestStatus.error)
      else if stripped.containsSubstr " F" then
        let testName := stripped.splitOn " " |>.head?.getD stripped
        some (testName, TestStatus.failed)
      else if stripped.containsSubstr " ok" then
        let testName := stripped.splitOn " " |>.head?.getD stripped
        some (testName, TestStatus.passed)
      else
        none
    else
      none

/-! ## Matplotlib Log Parser -/

/-- Parse Matplotlib test output (pytest-based but with extra substitutions).
Ported from `parse_log_matplotlib` in `utils/swe_log_parsers.py`. -/
def parseLogMatplotlib (log : String) : List (String × TestStatus) :=
  let lines := log.splitOn "\n"
  lines.filterMap fun line =>
    -- Strip mouse button substitutions
    let trimmed := (line.replace "MouseButton.LEFT" "1"
                       |>.replace "MouseButton.RIGHT" "3").trimAscii.toString
    if trimmed.startsWith "PASSED " then
      some ((trimmed.drop 7).toString.trimAscii.toString, TestStatus.passed)
    else if trimmed.startsWith "FAILED " then
      let rest := (trimmed.drop 7).toString.trimAscii.toString
      let name := (rest.replace " - " " ").splitOn " " |>.head?.getD rest
      some (name, TestStatus.failed)
    else if trimmed.startsWith "ERROR " then
      some ((trimmed.drop 6).toString.trimAscii.toString, TestStatus.error)
    else
      none

/-! ## Language-Specific Parsers -/

/-- Parse Rust (cargo test) output. -/
def parseLogCargo (log : String) : List (String × TestStatus) :=
  let lines := log.splitOn "\n"
  lines.filterMap fun line =>
    let trimmed := line.trimAscii.toString
    if trimmed.containsSubstr "... ok" then
      some (trimmed.splitOn " " |>.head?.getD trimmed, TestStatus.passed)
    else if trimmed.containsSubstr "... FAILED" then
      some (trimmed.splitOn " " |>.head?.getD trimmed, TestStatus.failed)
    else
      none

/-- Parse Go test output. -/
def parseLogGoTest (log : String) : List (String × TestStatus) :=
  let lines := log.splitOn "\n"
  lines.filterMap fun line =>
    let trimmed := line.trimAscii.toString
    if trimmed.startsWith "--- PASS:" then
      some ((trimmed.drop 10).toString.trimAscii.toString, TestStatus.passed)
    else if trimmed.startsWith "--- FAIL:" then
      some ((trimmed.drop 10).toString.trimAscii.toString, TestStatus.failed)
    else if trimmed.startsWith "--- SKIP:" then
      some ((trimmed.drop 10).toString.trimAscii.toString, TestStatus.skipped)
    else
      none

/-! ## Parser Registry -/

/-- Map from repository name to the appropriate log parser.
Ported from `MAP_REPO_TO_PARSER` in `utils/swe_log_parsers.py`.

Covers all repos in the SWE-bench Verified dataset. -/
def getParser (repoName : String) : String → List (String × TestStatus) :=
  -- Django
  if repoName == "django/django" then parseLogDjango
  -- Repos using pytest_v2 (astropy, scikit-learn, sphinx)
  else if repoName == "astropy/astropy" ||
          repoName == "scikit-learn/scikit-learn" ||
          repoName == "sphinx-doc/sphinx" then parseLogPytestV2
  -- Seaborn
  else if repoName == "mwaskom/seaborn" then parseLogSeaborn
  -- Sympy
  else if repoName == "sympy/sympy" then parseLogSympy
  -- Matplotlib
  else if repoName == "matplotlib/matplotlib" then parseLogMatplotlib
  -- Repos using pytest_options
  else if repoName == "pydicom/pydicom" ||
          repoName == "psf/requests" ||
          repoName == "pylint-dev/pylint" then parseLogPytestOptions
  -- All others use standard pytest (flask, marshmallow, pvlib, pyvista,
  -- sqlfluff, xarray, astroid, pylint, pytest-dev/pytest, dgm, etc.)
  else parseLogPytest

end DGM.Utils.LogParsers
