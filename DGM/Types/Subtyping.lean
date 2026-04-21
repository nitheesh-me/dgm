import DGM.Types.Basic
import DGM.Types.AgentSpec

/-!
# DGM.Types.Subtyping — Subtype Relations and Bound Tightening

Defines the subtyping lattice for agent specifications:
- `AgentSubtype`: when one agent refines another (behavioral subtyping)
- `Supertyping` / `BoundTightening`: when a child narrows the I/O bounds
- `SubtypeChain`: transitive chains of subtype relations through evolution

## Liskov Substitution Principle (LSP) for Agents
An agent `child` is a subtype of `parent` if:
- `child.InputDomain ⊇ parent.InputDomain` (contravariant inputs)
- `child.OutputDomain ⊆ parent.OutputDomain` (covariant outputs)
- All postconditions of `parent` are satisfied by `child`
-/
namespace DGM.Types

/-! ## Behavioral Subtyping -/

/-- Agent behavioral subtyping (Liskov-style).

`AgentSubtype specA specB` asserts that any agent satisfying `specA`
also satisfies `specB` — i.e., `specA` refines `specB`.

This models: `AgentImpl specA ≤ AgentImpl specB`. -/
structure AgentSubtype (specA specB : AgentSpec) where
  /-- Contravariant precondition: `specA` accepts at least everything `specB` does. -/
  preconditionWeakening : ∀ (input : AgentInput),
    specB.precondition input → specA.precondition input
  /-- Covariant postcondition: `specA`'s postcondition implies `specB`'s. -/
  postconditionStrengthening : ∀ (input : AgentInput) (output : AgentOutput),
    specA.postcondition input output → specB.postcondition input output
  /-- Invariant preservation: `specA`'s invariant implies `specB`'s. -/
  invariantPreservation : specA.invariant → specB.invariant
  /-- Stable domain inclusion: `specA`'s stable domain is at least as large. -/
  stableDomainInclusion : ∀ (input : AgentInput),
    specB.stableDomain input → specA.stableDomain input

/-- Reflexivity: every spec is a subtype of itself. -/
theorem AgentSubtype.refl (spec : AgentSpec) : AgentSubtype spec spec :=
  { preconditionWeakening := fun _ h => h
    postconditionStrengthening := fun _ _ h => h
    invariantPreservation := fun h => h
    stableDomainInclusion := fun _ h => h }

/-- Transitivity: subtyping composes. -/
theorem AgentSubtype.trans {a b c : AgentSpec}
    (hab : AgentSubtype a b) (hbc : AgentSubtype b c) : AgentSubtype a c :=
  { preconditionWeakening := fun input h =>
      hab.preconditionWeakening input (hbc.preconditionWeakening input h)
    postconditionStrengthening := fun input output h =>
      hbc.postconditionStrengthening input output (hab.postconditionStrengthening input output h)
    invariantPreservation := fun h =>
      hbc.invariantPreservation (hab.invariantPreservation h)
    stableDomainInclusion := fun input h =>
      hab.stableDomainInclusion input (hbc.stableDomainInclusion input h) }

/-! ## Bound Tightening (Supertyping) -/

/-- Bound tightening: the child *narrows* the acceptable output range
while accepting at least the same inputs.

This is useful when an upgrade makes the agent more precise — producing
a tighter set of outputs (higher quality patches, fewer false positives). -/
structure BoundTightening (specParent specChild : AgentSpec) where
  /-- Input domain is at least as wide (contravariant). -/
  inputWidening : ∀ (input : AgentInput),
    specParent.precondition input → specChild.precondition input
  /-- Output postcondition is strictly stronger (covariant tightening).
      Every output satisfying the child's postcondition also satisfies the parent's. -/
  outputTightening : ∀ (input : AgentInput) (output : AgentOutput),
    specChild.postcondition input output → specParent.postcondition input output
  /-- The child's postcondition is strictly stronger for at least one case. -/
  strictlyTighter : ∃ (input : AgentInput) (output : AgentOutput),
    specParent.postcondition input output ∧ ¬ specChild.postcondition input output

/-- Bound tightening implies subtyping. -/
theorem BoundTightening.toSubtype {specP specC : AgentSpec}
    (bt : BoundTightening specP specC)
    (invPres : specC.invariant → specP.invariant)
    (stablePres : ∀ (input : AgentInput),
      specP.stableDomain input → specC.stableDomain input)
    : AgentSubtype specC specP :=
  { preconditionWeakening := bt.inputWidening
    postconditionStrengthening := bt.outputTightening
    invariantPreservation := invPres
    stableDomainInclusion := stablePres }

/-! ## Subtype Chains Through Evolution -/

/-- A chain of subtype relations through evolution history.
Represents the transitive closure of evolution steps. -/
inductive SubtypeChain : AgentSpec → AgentSpec → Type where
  | refl  : (spec : AgentSpec) → SubtypeChain spec spec
  | step  : {a b c : AgentSpec} →
             AgentSubtype a b → SubtypeChain b c → SubtypeChain a c

/-- Extract the composite subtype relation from a chain. -/
def SubtypeChain.toSubtype {a b : AgentSpec} : SubtypeChain a b → AgentSubtype a b
  | .refl spec   => AgentSubtype.refl spec
  | .step hab tl => AgentSubtype.trans hab tl.toSubtype

/-! ## Coercion Between Agent Implementations -/

/-- Given a subtype proof, lift an implementation from the refined spec to the base spec. -/
def AgentImpl.coerce {specA specB : AgentSpec}
    (sub : AgentSubtype specA specB)
    (implA : AgentImpl specA) : AgentImpl specB :=
  { behavior       := implA.behavior
    invariantProof := sub.invariantPreservation implA.invariantProof
    score          := implA.score
    commitId       := implA.commitId
    parentCommitId := implA.parentCommitId }

end DGM.Types
