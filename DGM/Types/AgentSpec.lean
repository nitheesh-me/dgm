/-!
# DGM.Types.AgentSpec — Agent Specification & Implementation with Refinement Types

This module defines the formal specification framework for DGM agents.
An `AgentSpec` captures preconditions, postconditions, and invariants.
An `AgentImpl` carries a proof that it satisfies its specification.

## Key Concepts
- **AgentSpec**: What an agent must satisfy (behavioral contract)
- **AgentImpl**: An implementation that provably meets its AgentSpec
- **StableSubtype**: The invariant behavioral core across upgrades
- **UpgradeDelta**: The intended behavioral change in an upgrade
-/

import DGM.Types.Basic

namespace DGM.Types

/-! ## Domain & Behavior Modeling -/

/-- An abstract input to an agent (problem statement + context). -/
structure AgentInput where
  problemStatement : String
  repoPath         : String
  baseCommit       : String
  testDescription  : Option String := none
  instanceId       : Option String := none
  deriving Repr, Inhabited

/-- An abstract output from an agent (patch + metadata). -/
structure AgentOutput where
  patch            : String           -- the diff/patch produced
  resolved         : Bool             -- whether the issue was resolved
  testReport       : Option (List (String × Types.TestStatus)) := none
  deriving Repr, Inhabited

/-- An agent's behavior is a function from inputs to outputs (in IO). -/
abbrev AgentBehavior := AgentInput → IO AgentOutput

/-! ## Agent Specification (Behavioral Contract) -/

/-- A predicate on agent inputs (precondition domain). -/
abbrev InputPredicate := AgentInput → Prop

/-- A predicate on agent outputs (postcondition). -/
abbrev OutputPredicate := AgentOutput → Prop

/-- A relation between input and output (postcondition linking both). -/
abbrev IORelation := AgentInput → AgentOutput → Prop

/-- Formal specification of an agent's behavioral contract.

An `AgentSpec` defines:
- `precondition`: What inputs the agent is expected to handle
- `postcondition`: What must hold of the output given valid input
- `invariant`: A property that must hold throughout the agent's execution
- `stableDomain`: The subset of inputs where behavior must not change across upgrades
-/
structure AgentSpec where
  /-- Precondition: inputs the agent is designed to handle. -/
  precondition  : InputPredicate
  /-- Postcondition: output requirements given valid input. -/
  postcondition : IORelation
  /-- Invariant: must hold at all times during execution. -/
  invariant     : Prop
  /-- Stable domain: inputs where behavior is preserved across upgrades. -/
  stableDomain  : InputPredicate
  deriving Inhabited

/-- An agent implementation that carries a proof it satisfies its specification.

This is the core refinement type: `AgentImpl spec` is the subtype of
`AgentBehavior` values that provably satisfy `spec`. -/
structure AgentImpl (spec : AgentSpec) where
  /-- The actual behavior function. -/
  behavior : AgentBehavior
  /-- Proof that the invariant holds. -/
  invariantProof : spec.invariant
  /-- Score achieved on evaluation benchmark. -/
  score : Float
  /-- Unique identifier (commit hash). -/
  commitId : String
  /-- Parent commit (if evolved from another agent). -/
  parentCommitId : Option String := none

/-! ## Stable Subtype -/

/-- The stable subtype identifies behaviors that are invariant across upgrades.

Given two agents `parent` and `child`, `StableSubtype parent child` asserts
that for all inputs in the stable domain, the parent and child produce
equivalent outputs (modulo IO, which we axiomatize). -/
structure StableSubtype {spec : AgentSpec} (parent child : AgentImpl spec) where
  /-- For every input in the stable domain, both agents agree on resolution status.
      We model this as: if parent resolves an issue, child also resolves it. -/
  preservesResolution : ∀ (input : AgentInput),
    spec.stableDomain input →
    ∀ (parentOut childOut : AgentOutput),
    parentOut.resolved → childOut.resolved
  /-- The child's score is at least as good as the parent's on the stable domain. -/
  scoreNonRegression : child.score ≥ parent.score

/-! ## Upgrade Delta -/

/-- Predicate identifying the domain where behavioral change is intended. -/
abbrev DeltaDomain := InputPredicate

/-- An upgrade delta specifies *what* is intended to change.

The `UpgradeDelta` separates the intentional behavioral change from
the stable core, enabling verification that changes are targeted. -/
structure UpgradeDelta where
  /-- The domain of inputs where behavior is allowed to change. -/
  changeDomain : DeltaDomain
  /-- Description of the intended improvement. -/
  description : String
  /-- The upgrade specification: what the new behavior should satisfy. -/
  upgradeSpec : IORelation
  deriving Inhabited

/-- Proof that the delta domain is disjoint from the stable domain.
This ensures upgrades only affect intended areas. -/
structure DeltaStableDisjoint (spec : AgentSpec) (delta : UpgradeDelta) where
  disjoint : ∀ (input : AgentInput),
    spec.stableDomain input → ¬ delta.changeDomain input

/-! ## Agent with Full Provenance -/

/-- A fully-provenanced agent: implementation + its lineage and upgrade proof.
This is what lives in the evolution archive. -/
structure ProvenancedAgent (spec : AgentSpec) where
  /-- The agent implementation. -/
  impl : AgentImpl spec
  /-- The upgrade delta (if evolved). -/
  delta : Option UpgradeDelta := none
  /-- Generation number. -/
  generation : Nat := 0

end DGM.Types
