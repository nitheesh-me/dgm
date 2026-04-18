/-!
# DGM.Utils.LogParsers — Test Log Parsing

Parsers for extracting test results from different test framework logs.
Ported from: `utils/swe_log_parsers.py`
-/

import DGM.Types.Basic

namespace DGM.Utils.LogParsers

open DGM.Types

/-! ## Pytest Log Parser -/

/-- Parse pytest output into test results.
Ported from `parse_log_pytest` in `utils/swe_log_parsers.py`. -/
def parseLogPytest (log : String) : List (String × TestStatus) :=
  let lines := log.splitOn "\n"
  lines.filterMap fun line =>
    let trimmed := line.trim
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
  parseLogPytest log  -- Simplified; full impl handles brackets

/-! ## Django Test Log Parser -/

/-- Parse Django test output.
Ported from `parse_log_django` in `utils/swe_log_parsers.py`. -/
def parseLogDjango (log : String) : List (String × TestStatus) :=
  let lines := log.splitOn "\n"
  lines.filterMap fun line =>
    let trimmed := line.trim
    if trimmed.containsSubstr "... ok" then
      some (trimmed.splitOn " " |>.head?.getD trimmed, TestStatus.passed)
    else if trimmed.containsSubstr "... FAIL" then
      some (trimmed.splitOn " " |>.head?.getD trimmed, TestStatus.failed)
    else if trimmed.containsSubstr "... ERROR" then
      some (trimmed.splitOn " " |>.head?.getD trimmed, TestStatus.error)
    else
      none

/-! ## Language-Specific Parsers -/

/-- Parse Rust (cargo test) output. -/
def parseLogCargo (log : String) : List (String × TestStatus) :=
  let lines := log.splitOn "\n"
  lines.filterMap fun line =>
    let trimmed := line.trim
    if trimmed.containsSubstr "... ok" then
      let name := trimmed.splitOn " " |>.head?.getD trimmed
      some (name, TestStatus.passed)
    else if trimmed.containsSubstr "... FAILED" then
      let name := trimmed.splitOn " " |>.head?.getD trimmed
      some (name, TestStatus.failed)
    else
      none

/-- Parse Go test output. -/
def parseLogGoTest (log : String) : List (String × TestStatus) :=
  let lines := log.splitOn "\n"
  lines.filterMap fun line =>
    let trimmed := line.trim
    if trimmed.startsWith "--- PASS:" then
      some (trimmed.drop 10 |>.trim, TestStatus.passed)
    else if trimmed.startsWith "--- FAIL:" then
      some (trimmed.drop 10 |>.trim, TestStatus.failed)
    else if trimmed.startsWith "--- SKIP:" then
      some (trimmed.drop 10 |>.trim, TestStatus.skipped)
    else
      none

/-! ## Parser Registry -/

/-- Map from repository/language to the appropriate log parser.
Ported from `MAP_REPO_TO_PARSER` in `utils/swe_log_parsers.py`. -/
def getParser (repoOrLang : String) : String → List (String × TestStatus) :=
  if repoOrLang.containsSubstr "django" then
    parseLogDjango
  else if repoOrLang == "rust" then
    parseLogCargo
  else if repoOrLang == "go" then
    parseLogGoTest
  else
    parseLogPytest  -- Default

end DGM.Utils.LogParsers
