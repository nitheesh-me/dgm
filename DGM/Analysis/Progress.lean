/-!
# DGM.Analysis.Progress — Progress Tracking and Reporting

Track evolution progress across generations.
Ported from: `analysis/plot_progress.py` and `analysis/visualize_archive.py`

Note: Visualization (matplotlib, networkx) is kept in Python.
This module handles the data extraction and reporting in Lean 4.
-/

import DGM.Evolution.Archive

namespace DGM.Analysis.Progress

open DGM.Evolution

/-! ## Progress Data -/

/-- Progress data point for a single generation. -/
structure GenerationProgress where
  generation    : Nat
  archiveSize   : Nat
  bestScore     : Float
  worstScore    : Float
  avgScore      : Float
  numCompiled   : Nat
  numAttempted  : Nat
  deriving Repr, Inhabited

/-- Extract progress data from an archive. -/
def extractProgress (archive : ConcreteArchive) (generation : Nat) : GenerationProgress :=
  let scores := archive.entries.map (·.score)
  let avg := if scores.isEmpty then 0.0
    else scores.foldl (· + ·) 0.0 / Float.ofNat scores.length
  { generation := generation
    archiveSize := archive.entries.length
    bestScore := archive.bestScore
    worstScore := archive.worstScore
    avgScore := avg
    numCompiled := archive.entries.filter (·.isCompiled) |>.length
    numAttempted := archive.entries.length
  }

/-- Format progress as a human-readable report. -/
def formatProgressReport (progress : List GenerationProgress) : String :=
  let header := "Gen | Archive | Best    | Avg     | Compiled/Attempted"
  let separator := String.mk (List.replicate 60 '-')
  let rows := progress.map fun p =>
    s!"{p.generation} | {p.archiveSize} | {p.bestScore} | {p.avgScore} | {p.numCompiled}/{p.numAttempted}"
  String.intercalate "\n" ([header, separator] ++ rows)

/-- Write progress data to a CSV file for external plotting. -/
def writeProgressCSV (filePath : String) (progress : List GenerationProgress) : IO Unit := do
  let header := "generation,archive_size,best_score,worst_score,avg_score,num_compiled,num_attempted"
  let rows := progress.map fun p =>
    s!"{p.generation},{p.archiveSize},{p.bestScore},{p.worstScore},{p.avgScore},{p.numCompiled},{p.numAttempted}"
  let content := String.intercalate "\n" ([header] ++ rows)
  IO.FS.writeFile ⟨filePath⟩ content

/-! ## Archive Tree -/

/-- Node in the evolution tree (for visualization export). -/
structure TreeNode where
  runId       : String
  parentId    : String
  generation  : Nat
  score       : Float
  deriving Repr, Inhabited

/-- Extract the evolution tree structure for external visualization.
Produces nodes that can be exported to DOT/GraphViz format. -/
def extractTree (archive : ConcreteArchive) : List TreeNode :=
  archive.entries.map fun e =>
    { runId := e.runId
      parentId := e.parentCommit
      generation := e.generation
      score := e.score }

/-- Export evolution tree to DOT format for GraphViz visualization. -/
def exportDOT (tree : List TreeNode) : String :=
  let header := "digraph DGM_Evolution {\n  rankdir=TB;\n  node [shape=box];\n"
  let nodes := tree.map fun n =>
    s!"  \"{n.runId}\" [label=\"{n.runId}\\ngen={n.generation}\\nscore={n.score}\"];"
  let edges := tree.filter (·.parentId != "initial") |>.map fun n =>
    s!"  \"{n.parentId}\" -> \"{n.runId}\";"
  let footer := "}"
  String.intercalate "\n" ([header] ++ nodes ++ edges ++ [footer])

end DGM.Analysis.Progress
