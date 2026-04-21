import Lake
open Lake DSL

package dgm where
  leanOptions := #[
    ⟨`autoImplicit, false⟩
  ]

@[default_target]
lean_lib DGM where
  srcDir := "."
  roots := #[`DGM]

lean_exe dgm_main where
  root := `Main
