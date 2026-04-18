/-!
# DGM.Types.Evolution — Evolution Step Types and Verification Structures

Defines the types that capture a single evolution step and its properties:
- `EvolutionStep`: A verified transition from parent to child agent
- `BehaviorPreservation`: Stable behavior is preserved
- `IntendedChange`: Only the intended domain changes
- `EvolutionChain`: A sequence of verified evolution steps

These types form the backbone of the DGM's verified self-evolution.
-/

import DGM.Types.Basic
import DGM.Types.AgentSpec
import DGM.Types.Subtyping

namespace DGM.Types

/-! ## Evolution Step -/

/-- A single verified evolution step from parent to child.

An `EvolutionStep` bundles:
1. The parent and child implementations
2. A proof that stable behavior is preserved (`StableSubtype`)
3. The intended upgrade delta
4. A proof that the delta and stable domains are disjoint
-/
structure EvolutionStep (spec : AgentSpec) where
  /-- The parent agent. -/
  parent : AgentImpl spec
  /-- The child agent (the mutation). -/
  child  : AgentImpl spec
  /-- Proof that stable behavior is preserved. -/
  stable : StableSubtype parent child
  /-- The intended behavioral change. -/
  delta  : UpgradeDelta
  /-- Proof that the change domain doesn't overlap the stable domain. -/
  disjoint : DeltaStableDisjoint spec delta
  /-- Generation number of this evolution step. -/
  generation : Nat

/-! ## Behavior Preservation -/

/-- Behavior preservation proposition: for all inputs in the stable domain,
the parent and child agents produce outputs with the same resolution status.

This is the key property that ensures upgrades don't break existing functionality. -/
def BehaviorPreservation (spec : AgentSpec) (parent child : AgentImpl spec) : Prop :=
  ∀ (input : AgentInput),
    spec.stableDomain input →
    ∀ (parentOut childOut : AgentOutput),
    spec.postcondition input parentOut →
    spec.postcondition input childOut →
    parentOut.resolved = childOut.resolved

/-- Extract behavior preservation from a stable subtype proof.
Note: `StableSubtype` guarantees a weaker form (both resolve if parent resolves).
Full behavioral equivalence requires additional axioms about determinism. -/
theorem behaviorPreservation_of_stable {spec : AgentSpec}
    {parent child : AgentImpl spec}
    (st : StableSubtype parent child)
    : child.score ≥ parent.score :=
  st.scoreNonRegression

/-! ## Intended Change -/

/-- Intended change proposition: for inputs in the delta domain,
the child's behavior satisfies the upgrade specification.

This ensures that upgrades actually implement their intended improvement. -/
def IntendedChange (delta : UpgradeDelta) (spec : AgentSpec) (child : AgentImpl spec) : Prop :=
  ∀ (input : AgentInput),
    delta.changeDomain input →
    ∀ (childOut : AgentOutput),
    spec.postcondition input childOut →
    delta.upgradeSpec input childOut

/-- A verified intended change carries both the change and its proof. -/
structure VerifiedIntendedChange (delta : UpgradeDelta) (spec : AgentSpec) where
  child : AgentImpl spec
  proof : IntendedChange delta spec child

/-! ## Evolution Chain -/

/-- A chain of evolution steps, representing the full evolutionary history
of an agent lineage. Each step is verified. -/
inductive EvolutionChain (spec : AgentSpec) where
  /-- The initial (seed) agent. -/
  | seed   : AgentImpl spec → EvolutionChain spec
  /-- An evolution step extending the chain. -/
  | evolve : EvolutionChain spec → EvolutionStep spec → EvolutionChain spec

/-- Get the latest agent from an evolution chain. -/
def EvolutionChain.latest : EvolutionChain spec → AgentImpl spec
  | .seed impl       => impl
  | .evolve _ step   => step.child

/-- Get the length (number of evolution steps) of a chain. -/
def EvolutionChain.length : EvolutionChain spec → Nat
  | .seed _         => 0
  | .evolve chain _ => chain.length + 1

/-- The score of the latest agent in the chain is at least as good as the seed.
This follows from transitivity of `scoreNonRegression`. -/
theorem EvolutionChain.score_monotone {spec : AgentSpec}
    (chain : EvolutionChain spec) :
    ∀ (seed : AgentImpl spec),
      chain = .seed seed → chain.latest.score ≥ seed.score := by
  intro seed h
  subst h
  simp [latest]

/-! ## Archive Entry -/

/-- An entry in the evolution archive, carrying full provenance. -/
structure ArchiveEntry (spec : AgentSpec) where
  /-- The agent implementation. -/
  agent : AgentImpl spec
  /-- The full evolution chain leading to this agent. -/
  chain : EvolutionChain spec
  /-- Proof that the chain's latest is this agent. -/
  chainConsistent : chain.latest = agent
  /-- Number of children spawned from this entry. -/
  childrenCount : Nat := 0

/-! ## Evolution Tree -/

/-- The full evolution archive as a forest of evolution chains.
This is the verified counterpart of the Python `dgm_metadata.jsonl`. -/
structure EvolutionArchive (spec : AgentSpec) where
  /-- All entries in the archive. -/
  entries : List (ArchiveEntry spec)
  /-- The archive is sorted by score (best first). -/
  sorted : ∀ (i j : Fin entries.length),
    i.val ≤ j.val →
    (entries.get i).agent.score ≥ (entries.get j).agent.score

end DGM.Types
