/-!
# DGM.Evolution.Archive — Verified Evolution Archive

The archive stores all agents in the evolutionary process as a verified tree.
Each node carries its evolution proof and performance metrics.
Ported from: `utils/evo_utils.py` and archive logic in `DGM_outer.py`
-/

import DGM.Types.Evolution
import DGM.Types.Basic

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

/-! ## Parent Selection -/

/-- Selection methods for choosing parents.
Ported from `choose_selfimproves` in `DGM_outer.py`. -/

/-- Score-proportional selection weights. -/
def scoreProportionalWeights (entries : List ArchiveMetadata) : List (ArchiveMetadata × Float) :=
  let scores := entries.map (·.score)
  let minScore := scores.foldl min 1.0
  let weights := entries.map fun e => (e, e.score - minScore + 0.01)
  weights

/-- Score-child-proportional selection: favors high-scoring entries with fewer children.
This is the default selection method in DGM. -/
def scoreChildProportionalWeights (entries : List ArchiveMetadata)
    : List (ArchiveMetadata × Float) :=
  let scores := entries.map (·.score)
  let minScore := scores.foldl min 1.0
  entries.map fun e =>
    let scoreWeight := e.score - minScore + 0.01
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
    -- Random selection (simplified: just take first `count`)
    return archive.entries.take count
  | .best =>
    -- Best score selection
    let sorted := archive.entries.mergeSort (fun a b => a.score > b.score)
    return sorted.take count
  | .scoreProp =>
    -- Score-proportional selection
    let _weights := scoreProportionalWeights archive.entries
    -- TODO: weighted random sampling
    return archive.entries.take count
  | .scoreChildProp =>
    -- Score-child-proportional selection (default)
    let _weights := scoreChildProportionalWeights archive.entries
    -- TODO: weighted random sampling
    return archive.entries.take count

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
  -- In production: read metadata files and follow parent chain
  -- Returns list of patch file paths in order [oldest, ..., newest]
  return []

/-! ## Archive Persistence -/

/-- Load archive from a JSONL metadata file.
Ported from `load_dgm_metadata` in `utils/evo_utils.py`. -/
def loadArchive (metadataPath : String) : IO ConcreteArchive := do
  let exists ← System.FilePath.pathExists ⟨metadataPath⟩
  if !exists then
    return ConcreteArchive.empty
  let content ← IO.FS.readFile ⟨metadataPath⟩
  let lines := content.splitOn "\n" |>.filter (·.length > 0)
  -- Parse each JSONL line into ArchiveMetadata
  -- TODO: proper JSON parsing
  let _entries := lines.map fun _line => (ArchiveMetadata.mk "" "" "" 0 0.0 false 0)
  return { entries := [] }

/-- Save archive state to JSONL metadata file. -/
def saveArchiveState (metadataPath : String) (generation : Nat)
    (archive : ConcreteArchive) (children : List String) : IO Unit := do
  let line := s!"\{\"generation\": {generation}, \"archive_size\": {archive.entries.length}, \"children\": {children.length}}"
  IO.FS.Handle.mk ⟨metadataPath⟩ .append >>= fun h =>
    h.putStrLn line

end DGM.Evolution
