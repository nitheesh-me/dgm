/-!
# DGM.Evolution.Archive — Verified Evolution Archive

The archive stores all agents in the evolutionary process as a verified tree.
Each node carries its evolution proof and performance metrics.
Ported from: `utils/evo_utils.py` and archive logic in `DGM_outer.py`
-/

import DGM.Types.Evolution
import DGM.Types.Basic
import DGM.Utils.Common

namespace DGM.Evolution

open DGM.Types

/-! ## Archive Operations -/

/-- Metadata stored alongside each archive entry (serializable). -/
structure ArchiveMetadata where
  runId        : String
  parentCommit : String
  entry        : String
  generation   : Nat
  score        : Float
  isCompiled   : Bool
  childrenCount : Nat := 0
  deriving Repr, Inhabited

/-- Concrete archive: a list of entries with metadata.
This is the runtime representation, separate from the verified `EvolutionArchive`. -/
structure ConcreteArchive where
  entries : List ArchiveMetadata
  deriving Repr, Inhabited

/-- Create an empty archive. -/
def ConcreteArchive.empty : ConcreteArchive := { entries := [] }

/-- Add an entry to the archive. -/
def ConcreteArchive.add (archive : ConcreteArchive) (entry : ArchiveMetadata)
    : ConcreteArchive :=
  { entries := archive.entries ++ [entry] }

/-- Get the best score in the archive. -/
def ConcreteArchive.bestScore (archive : ConcreteArchive) : Float :=
  match archive.entries with
  | [] => 0.0
  | es => es.foldl (fun best e => if e.score > best then e.score else best) 0.0

/-- Get the worst score in the archive. -/
def ConcreteArchive.worstScore (archive : ConcreteArchive) : Float :=
  match archive.entries with
  | [] => 0.0
  | e :: es => es.foldl (fun worst e => if e.score < worst then e.score else worst) e.score

/-! ## Random Sampling -/

/-- Generate a pseudo-random Float in [0, 1) using nanosecond clock.
Uses lower bits of nanosecond counter for entropy.
NOTE: This is not cryptographically secure and may have low entropy
in tight loops. For production, consider using a proper PRNG seeded
from system entropy. Sufficient for parent selection where slight
bias is acceptable. -/
def randomFloat : IO Float := do
  let ns ← IO.monoNanosNow
  -- Use lower bits of nanosecond counter for randomness
  let r := (ns % 1000000007).toFloat / 1000000007.0
  return r

/-- Weighted random selection: pick one item from a weighted list.
Uses cumulative distribution sampling (roulette wheel).
Ported from `random.choices` in Python. -/
def weightedRandomChoice (items : List (α × Float)) : IO α := do
  let totalWeight := items.foldl (fun acc (_, w) => acc + w) 0.0
  if totalWeight ≤ 0.0 then
    -- Fallback: return the first item
    match items with
    | (a, _) :: _ => return a
    | [] => throw <| IO.userError "weightedRandomChoice: empty list"
  let r ← randomFloat
  let target := r * totalWeight
  let mut cumulative := 0.0
  for (item, weight) in items do
    cumulative := cumulative + weight
    if cumulative ≥ target then
      return item
  -- Fallback: return last item
  match items.getLast? with
  | some (a, _) => return a
  | none => throw <| IO.userError "weightedRandomChoice: empty list"

/-- Select `k` items with replacement from a weighted list. -/
def weightedRandomChoices (items : List (α × Float)) (k : Nat) : IO (List α) := do
  let mut results : List α := []
  for _ in List.range k do
    let item ← weightedRandomChoice items
    results := results ++ [item]
  return results

/-! ## Selection Methods -/

/-- Selection methods for choosing parents.
Ported from `choose_selfimproves` in `DGM_outer.py`. -/

/-- Sigmoid function for score scaling (matching Python's implementation). -/
def sigmoid (x : Float) : Float :=
  1.0 / (1.0 + Float.exp (-(10.0 * (x - 0.5))))

/-- Score-proportional selection weights.
Applies sigmoid scaling to scores, matching Python:
`scores = [1 / (1 + math.exp(-10*(score-0.5))) for score in scores]` -/
def scoreProportionalWeights (entries : List ArchiveMetadata) : List (ArchiveMetadata × Float) :=
  entries.map fun e => (e, sigmoid e.score)

/-- Score-child-proportional selection: favors high-scoring entries with fewer children.
This is the default selection method in DGM.
Matching Python:
```
scores = [sigmoid(score) for score in scores]
children_counts = [1 / (1 + count) for count in children_counts]
probabilities = [score * count for score, count in zip(scores, children_counts)]
``` -/
def scoreChildProportionalWeights (entries : List ArchiveMetadata)
    : List (ArchiveMetadata × Float) :=
  entries.map fun e =>
    let scoreWeight := sigmoid e.score
    let childPenalty := 1.0 / (Float.ofNat e.childrenCount + 1.0)
    (e, scoreWeight * childPenalty)

/-- Choose parents for self-improvement using the given selection method.
Ported from `choose_selfimproves` in `DGM_outer.py`. -/
def chooseParents (archive : ConcreteArchive) (count : Nat)
    (method : SelectionMethod) : IO (List ArchiveMetadata) := do
  if archive.entries.isEmpty then
    return []
  match method with
  | .random =>
    -- Random selection with replacement
    let uniform := archive.entries.map fun e => (e, 1.0)
    weightedRandomChoices uniform count
  | .best =>
    -- Best score selection
    let sorted := archive.entries.mergeSort (fun a b => a.score > b.score)
    let top := sorted.take (min count sorted.length)
    -- If not enough, repeat from top
    if top.length ≥ count then return top.take count
    let remaining := count - top.length
    let extras ← weightedRandomChoices (top.map fun e => (e, 1.0)) remaining
    return top ++ extras
  | .scoreProp =>
    -- Score-proportional selection (roulette wheel)
    let weights := scoreProportionalWeights archive.entries
    weightedRandomChoices weights count
  | .scoreChildProp =>
    -- Score-child-proportional selection (default method in DGM)
    let weights := scoreChildProportionalWeights archive.entries
    weightedRandomChoices weights count

/-! ## Archive Update -/

/-- Check if a run qualifies for archive admission.
Ported from `update_archive` logic in `DGM_outer.py`. -/
def qualifiesForAdmission (archive : ConcreteArchive) (score : Float)
    (noiseLeeway : Float := 0.01) : Bool :=
  match archive.entries with
  | [] => true
  | _  => score ≥ archive.worstScore - noiseLeeway

/-- Update the archive with new run results.
Ported from `update_archive` in `DGM_outer.py`. -/
def updateArchive (archive : ConcreteArchive)
    (newEntries : List ArchiveMetadata) (noiseLeeway : Float := 0.01)
    : ConcreteArchive :=
  let qualified := newEntries.filter fun e =>
    qualifiesForAdmission archive e.score noiseLeeway
  let combined := archive.entries ++ qualified
  let sorted := combined.mergeSort (fun a b => a.score > b.score)
  { entries := sorted }

/-! ## Model Patch Path Tracing -/

/-- Trace the chain of model patches from initial to the given commit.
Ported from `get_model_patch_paths` in `utils/evo_utils.py`.

This recursively follows parent commits to build the full patch chain. -/
def getModelPatchPaths (rootDir dgmDir parentCommit : String) : IO (List String) := do
  -- Recursively trace parent chain
  if parentCommit == "initial" then
    return []
  let metadataPath := s!"{dgmDir}/{parentCommit}/metadata.json"
  let exists ← System.FilePath.pathExists ⟨metadataPath⟩
  if !exists then
    return []
  let content ← IO.FS.readFile ⟨metadataPath⟩
  -- Extract parent_commit from JSON
  let grandparent := match content.splitOn "\"parent_commit\": \"" with
    | [_, rest] => match rest.splitOn "\"" with | val :: _ => val | _ => "initial"
    | _ => "initial"
  -- Recurse to get full chain
  let ancestorPatches ← getModelPatchPaths rootDir dgmDir grandparent
  let patchPath := s!"{dgmDir}/{parentCommit}/model_patch.diff"
  let patchExists ← System.FilePath.pathExists ⟨patchPath⟩
  if patchExists then
    return ancestorPatches ++ [patchPath]
  else
    return ancestorPatches

/-! ## Archive Persistence -/

/-- Load archive from a JSONL metadata file.
Ported from `load_dgm_metadata` in `utils/evo_utils.py`. -/
def loadArchive (metadataPath : String) : IO ConcreteArchive := do
  let exists ← System.FilePath.pathExists ⟨metadataPath⟩
  if !exists then
    return ConcreteArchive.empty
  let content ← IO.FS.readFile ⟨metadataPath⟩
  let lines := content.splitOn "\n" |>.filter (·.length > 0)
  -- Parse the last line to get the most recent archive state
  match lines.getLast? with
  | none => return ConcreteArchive.empty
  | some lastLine =>
    -- Extract archive entries from the line
    -- The line has format: {"generation": N, "archive": ["id1", "id2", ...], ...}
    let archiveIds := extractArchiveIds lastLine
    let entries := archiveIds.map fun id =>
      { runId := id, parentCommit := "", entry := id, generation := 0,
        score := 0.0, isCompiled := true, childrenCount := 0 : ArchiveMetadata }
    return { entries := entries }
where
  extractArchiveIds (line : String) : List String :=
    match line.splitOn "\"archive\": [" with
    | [_, rest] =>
      match rest.splitOn "]" with
      | arrayContent :: _ =>
        arrayContent.splitOn ","
          |>.map (·.trim.replace "\"" "")
          |>.filter (·.length > 0)
      | _ => []
    | _ => []

/-- Save archive state to JSONL metadata file.
Matches Python format:
```json
{"generation": N, "selfimprove_entries": [...], "children": [...], "children_compiled": [...], "archive": [...]}
``` -/
def saveArchiveState (metadataPath : String) (generation : Nat)
    (archive : ConcreteArchive) (children : List String) : IO Unit := do
  let archiveIds := archive.entries.map (·.runId)
  let archiveJson := "[" ++ String.intercalate ", " (archiveIds.map fun id => s!"\"{id}\"") ++ "]"
  let childrenJson := "[" ++ String.intercalate ", " (children.map fun id => s!"\"{id}\"") ++ "]"
  let line := s!"\{\"generation\": {generation}, \"children\": {childrenJson}, " ++
    s!"\"children_compiled\": {childrenJson}, \"archive\": {archiveJson}}"
  -- Ensure parent directory exists
  let dir := System.FilePath.mk metadataPath |>.parent
  match dir with
  | some d => IO.FS.createDirAll d
  | none => pure ()
  IO.FS.Handle.mk ⟨metadataPath⟩ .append >>= fun h =>
    h.putStrLn line

end DGM.Evolution
