import DGM.Types.Basic

/-!
# DGM.Utils.Git — Git Operations

Git operations for diff, reset, apply, and patch management.
Ported from: `utils/git_utils.py`
-/

namespace DGM.Utils.Git

/-! ## Git Operations -/

/-- Get the current git commit hash.
Ported from `get_git_commit_hash`. -/
def getCommitHash (repoPath : String := ".") : IO String := do
  let result ← IO.Process.output {
    cmd := "git"
    args := #["--no-pager", "-C", repoPath, "rev-parse", "HEAD"]
  }
  if result.exitCode != 0 then
    throw <| IO.userError s!"git rev-parse failed: {result.stderr}"
  return result.stdout.trimAscii.toString

/-- Get the diff between current state and a commit.
Ported from `diff_versus_commit`.
Includes both tracked changes and untracked files. -/
def diffVersusCommit (repoPath commit : String) : IO String := do
  -- Tracked changes
  let diffResult ← IO.Process.output {
    cmd := "git"
    args := #["--no-pager", "-C", repoPath, "diff", commit]
  }
  -- Untracked files
  let untrackedResult ← IO.Process.output {
    cmd := "git"
    args := #["--no-pager", "-C", repoPath, "ls-files", "--others", "--exclude-standard"]
  }
  let untrackedFiles := untrackedResult.stdout.splitOn "\n" |>.filter (·.length > 0)

  let mut fullDiff := diffResult.stdout

  -- Add untracked file contents to diff
  for file in untrackedFiles do
    let content ← IO.FS.readFile ⟨s!"{repoPath}/{file}"⟩
    fullDiff := fullDiff ++ s!"\n--- /dev/null\n+++ b/{file}\n" ++
      (content.splitOn "\n" |>.map (s!"+{·}") |> String.intercalate "\n")

  return fullDiff

/-- Reset repository to a specific commit (hard reset + clean).
Ported from `reset_to_commit`. -/
def resetToCommit (repoPath commit : String) : IO Unit := do
  let resetResult ← IO.Process.output {
    cmd := "git"
    args := #["--no-pager", "-C", repoPath, "reset", "--hard", commit]
  }
  if resetResult.exitCode != 0 then
    throw <| IO.userError s!"git reset failed: {resetResult.stderr}"

  let cleanResult ← IO.Process.output {
    cmd := "git"
    args := #["--no-pager", "-C", repoPath, "clean", "-fdx"]
  }
  if cleanResult.exitCode != 0 then
    throw <| IO.userError s!"git clean failed: {cleanResult.stderr}"

/-- Apply a patch to the repository.
Ported from `apply_patch`. Uses `--reject` to apply what it can. -/
def applyPatch (repoPath patch : String) : IO Unit := do
  -- Write patch to temp file
  let patchFile := s!"/tmp/dgm_patch_{← IO.monoNanosNow}.diff"
  IO.FS.writeFile ⟨patchFile⟩ patch

  let result ← IO.Process.output {
    cmd := "git"
    args := #["--no-pager", "-C", repoPath, "apply", "--reject", "--whitespace=fix", patchFile]
  }
  -- git apply --reject may have non-zero exit code but still apply parts
  if result.exitCode != 0 then
    IO.eprintln s!"Warning: git apply had errors: {result.stderr}"

  -- Clean up temp file
  IO.FS.removeFile ⟨patchFile⟩

/-- Filter a patch to only include changes to specific files.
Ported from `filter_patch_by_files`. -/
def filterPatchByFiles (patch : String) (targetFiles : List String) : String :=
  let sections := patch.splitOn "diff --git"
  let filtered := sections.filter fun sect =>
    targetFiles.any fun file => sect.containsSubstr file
  String.intercalate "diff --git" filtered

/-- Remove patch sections matching a keyword.
Ported from `remove_patch_by_files`. -/
def removePatchByKeyword (patch : String) (keyword : String := "polyglot") : String :=
  let sections := patch.splitOn "diff --git"
  let filtered := sections.filter fun sect =>
    !sect.containsSubstr keyword
  String.intercalate "diff --git" filtered

end DGM.Utils.Git
