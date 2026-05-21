import Lake
open Lake DSL

/-! # `LPCore` build configuration

  Pure-Lean data vocabulary (`Problem`, `Options`, `Solution`,
  `Certificate`, `SolveError`, supporting enums + validators) plus
  the `LPBackend` record. No native dependencies, no `moreLinkArgs`.

  This is the shared seam that `kim-em/soplex-ffi`,
  `kim-em/lp-verify`, `kim-em/lp-tactic`, and every
  `kim-em/lp-backend-*` package depends on.
-/

package LPCore

@[default_target]
lean_lib LPCore where
  roots := #[`LPCore]
  globs := #[`LPCore, `LPCore.Types, `LPCore.Validate, `LPCore.Backend]
