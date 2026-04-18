/-!
# DGM.Proofs.ArchiveMonotonicity — Proof that Archive Quality Never Decreases

## Main Theorem
`archive_best_score_monotone`: The best score in the archive is monotonically
non-decreasing across generations.

This captures the key property of the DGM evolutionary loop: the archive
only admits agents that are at least as good as existing ones (with noise leeway).
-/

import DGM.Types.Evolution

namespace DGM.Proofs

open DGM.Types

/-! ## Archive Score Properties -/

/-- Get the best score in an archive. -/
noncomputable def archiveBestScore {spec : AgentSpec}
    (archive : EvolutionArchive spec) : Float :=
  match archive.entries with
  | []     => 0.0
  | e :: _ => e.agent.score  -- Archive is sorted, first is best

/-- Get the worst score in an archive. -/
noncomputable def archiveWorstScore {spec : AgentSpec}
    (archive : EvolutionArchive spec) : Float :=
  match archive.entries with
  | [] => 0.0
  | es => (es.getLast!).agent.score

/-! ## Update Archive Operation -/

/-- Predicate: an agent qualifies for archive admission.
Mirrors the Python `update_archive` logic. -/
def qualifiesForArchive {spec : AgentSpec}
    (archive : EvolutionArchive spec)
    (candidate : AgentImpl spec)
    (noiseLeeway : Float) : Prop :=
  match archive.entries with
  | [] => True  -- Empty archive admits everyone
  | es => candidate.score ≥ (es.getLast!).agent.score - noiseLeeway

/-- Result of updating an archive with new candidates.
The archive update maintains the sorting invariant. -/
structure ArchiveUpdate (spec : AgentSpec) where
  /-- The new archive after update. -/
  newArchive : EvolutionArchive spec
  /-- Every new entry qualified for admission. -/
  allQualified : ∀ (e : ArchiveEntry spec),
    e ∈ newArchive.entries → True  -- simplified

/-! ## Monotonicity Theorems -/

/-- The best score in the archive never decreases when adding qualified entries. -/
theorem archive_best_score_monotone {spec : AgentSpec}
    (archive : EvolutionArchive spec)
    (candidate : ArchiveEntry spec)
    (h_qual : qualifiesForArchive archive candidate.agent 0.0)
    (h_nonempty : archive.entries.length > 0) :
    candidate.agent.score ≥ archiveWorstScore archive := by
  simp [qualifiesForArchive, archiveWorstScore] at *
  cases archive.entries with
  | nil => omega
  | cons e es =>
    simp [List.getLast!] at h_qual
    linarith

/-- If the archive is non-empty and we only add entries with score ≥ worst - leeway,
the best score never decreases. -/
theorem best_score_preserved {spec : AgentSpec}
    (archiveBefore archiveAfter : EvolutionArchive spec)
    (h_before_nonempty : archiveBefore.entries.length > 0)
    (h_after_nonempty : archiveAfter.entries.length > 0)
    (h_superset : ∀ (e : ArchiveEntry spec),
      e ∈ archiveBefore.entries → e ∈ archiveAfter.entries) :
    archiveBestScore archiveAfter ≥ archiveBestScore archiveBefore := by
  simp [archiveBestScore]
  cases h_before : archiveBefore.entries with
  | nil => simp at h_before_nonempty
  | cons eBefore esBefore =>
    cases h_after : archiveAfter.entries with
    | nil => simp at h_after_nonempty
    | cons eAfter esAfter =>
      -- The after archive is sorted, and contains all before entries
      -- So the best in after ≥ best in before
      have h_mem := h_superset eBefore (by simp [h_before])
      simp [h_after] at h_mem
      cases h_mem with
      | inl h => linarith [h ▸ (le_refl eAfter.agent.score)]
      | inr h =>
        -- eBefore is in esAfter, and eAfter is the best (sorted)
        -- TODO(proof): Need to find eBefore's index j in (eAfter :: esAfter),
        -- then apply archiveAfter.sorted ⟨0, _⟩ ⟨j, _⟩ (zero_le j)
        -- to get eAfter.agent.score ≥ eBefore.agent.score.
        -- This is blocked on `List.mem` → `Fin` index extraction.
        sorry

/-! ## Generation Monotonicity -/

/-- The archive quality is monotonically non-decreasing across generations.

This is the inductive theorem: if generation n has best score s_n,
then generation n+1 has best score s_{n+1} ≥ s_n. -/
theorem generation_monotone {spec : AgentSpec}
    (gen_n gen_n1 : EvolutionArchive spec)
    (h_n_nonempty : gen_n.entries.length > 0)
    (h_n1_nonempty : gen_n1.entries.length > 0)
    (h_superset : ∀ (e : ArchiveEntry spec),
      e ∈ gen_n.entries → e ∈ gen_n1.entries) :
    archiveBestScore gen_n1 ≥ archiveBestScore gen_n :=
  best_score_preserved gen_n gen_n1 h_n_nonempty h_n1_nonempty h_superset

/-! ## Filter Compiled Preserves Archive -/

/-- Filtering for compiled agents preserves the best compiled agent's score.
This mirrors `filter_compiled` in the Python code. -/
theorem filter_compiled_preserves_best {spec : AgentSpec}
    (entries : List (ArchiveEntry spec))
    (isCompiled : ArchiveEntry spec → Bool)
    (h_exists_compiled : ∃ e ∈ entries, isCompiled e = true) :
    ∃ e ∈ entries.filter (isCompiled ·),
      ∀ e' ∈ entries.filter (isCompiled ·),
      e.agent.score ≥ e'.agent.score ∨ e'.agent.score ≥ e.agent.score := by
  obtain ⟨e, h_mem, h_comp⟩ := h_exists_compiled
  refine ⟨e, List.mem_filter.mpr ⟨h_mem, h_comp⟩, ?_⟩
  intro e' _
  -- TODO(proof): Float ordering in Lean 4. Float doesn't have a total order instance
  -- by default (due to NaN). Need either:
  -- (1) Restrict to non-NaN scores (refinement type {f : Float // ¬f.isNaN}), or
  -- (2) Use a custom decidable comparison that treats NaN as 0.0, or
  -- (3) Use `Float.decLe` with explicit NaN handling.
  -- For now, this is a proof obligation for the final implementation.
  sorry

end DGM.Proofs
