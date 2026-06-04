/-
  Top-level entry point for `LPCore`: the shared LP vocabulary and
  the `LPBackend` record.

  Pure Lean, no native dependencies. Re-exported by `leanprover/lp`
  through `LP.Core`, and by `leanprover/soplex-ffi` through
  `SoplexFFI.Types` / `SoplexFFI.Validate` so existing consumers
  keep working.
-/

import LPCore.Types
import LPCore.Validate
import LPCore.Backend
