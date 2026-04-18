import DGM.Types.Basic
import DGM.Types.AgentSpec
import DGM.Types.Subtyping
import DGM.Types.Evolution
import DGM.Proofs.Stability
import DGM.Proofs.BoundTightening
import DGM.Proofs.UpgradeCorrectness
import DGM.Proofs.ArchiveMonotonicity
import DGM.Tools.Tool
import DGM.Tools.Bash
import DGM.Tools.Edit
import DGM.Agent.MockLLM
import DGM.Agent.LLM
import DGM.Agent.CodingAgent
import DGM.Agent.PolyglotAgent
import DGM.Evolution.Archive
import DGM.Evolution.SelfImprove
import DGM.Evolution.Outer
import DGM.Utils.Docker
import DGM.Utils.Git
import DGM.Utils.Common
import DGM.Utils.EvalUtils
import DGM.Utils.LogParsers
import DGM.Eval.SWEBench
import DGM.Eval.Polyglot
import DGM.Prompts.SelfImprovement
import DGM.Prompts.DiagnoseImprovement
import DGM.Prompts.TestRepo
import DGM.Prompts.ToolUse
import DGM.Analysis.Progress

/-!
# Darwin Gödel Machine — Lean 4 Implementation

A formally verified self-improving AI agent system.

## Module Structure
- `DGM.Types`      — Core type-theoretic foundation (refinement types, subtyping)
- `DGM.Evolution`  — Evolution engine with verified properties
- `DGM.Agent`      — Agent and LLM interface
- `DGM.Tools`      — Tool system (bash, editor)
- `DGM.Utils`      — Utility functions (Docker, Git, IO helpers)
- `DGM.Eval`       — Evaluation harnesses (SWE-bench, Polyglot)
- `DGM.Prompts`    — Prompt templates and construction
- `DGM.Proofs`     — Formal proofs of evolution properties
- `DGM.Analysis`   — Progress tracking and visualization
-/
