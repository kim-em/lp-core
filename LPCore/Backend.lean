/-
  The `LPBackend` record.

  This is the abstraction every concrete LP solver implements: a name,
  a default priority, an `IO`-typed `solveExact`, and a lazy `probe`.
  The verifier and tactic layers depend on `LPBackend`; concrete
  backends produce it; the tactic layer's registry stores them.

  Pure Lean, no native dependencies.
-/

import LPCore.Types

namespace LP

/-- Concrete LP solver backend.

    A backend takes a normalized `Problem` (and the `Options` that
    came with it) and returns either an error or a `Solution` whose
    `Certificate` the pure-Lean verifier can check.

    `solveExact` is `IO`-typed because the most useful non-FFI
    backends (out-of-process subprocess wrappers, future remote
    solvers) need `IO`. Synchronous backends like the SoPlex FFI
    lift their `Except` result with `pure`. -/
structure LPBackend where
  /-- Stable, machine-readable identifier. Used as the registry key
      and as the value of `set_option lp.backend`. Conventionally a
      short lowercase string with `-` separators (e.g. `"soplex-ffi"`,
      `"soplex-json"`, `"pure"`). -/
  name : String
  /-- Default priority when this backend is one of several registered.
      Lower runs first. Reserved bands:

      *  10  — fast native binding (FFI),
      *  50  — out-of-process subprocess (JSON),
      * 100  — pure-Lean reference,
      * 1000 — experimental / opt-in.

      The `leanprover/lp-tactic` registry's `dispatchSolveExact` picks
      the first backend (in this order) whose probe succeeds. A
      future tactic-side override surface (`set_option lp.backend` /
      `(backend := <ident>)`) will let callers pin a specific
      backend by name; it is not implemented yet. Do not re-register
      the same name with a different priority. -/
  defaultPriority : Nat := 100
  /-- Solve a validated LP and return its certificate. The argument is
      the post-`validate` problem; backends should not re-run
      `validate`. Backends are responsible for any solver-side
      canonicalization (`negateObjective` etc.). -/
  solveExact : {m n : Nat} → Options → Problem m n →
               IO (Except SolveError (Solution m n))
  /-- Lazy pre-flight probe: is this backend usable in the current
      process? `.ok ()` on success, a human-readable string on miss
      (e.g. `"executable `soplex` not on PATH"`, `"shared library
      failed to load: ..."`). Default `pure (.ok ())`.

      Probes run only when the tactic actually consults fallback. They
      never run during `initialize`. -/
  probe : IO (Except String Unit) := pure (.ok ())

namespace LPBackend

/-- Strict-less order on backends for fallback iteration: lower
    `defaultPriority` runs first; ties break on lexicographic `name`. -/
def lt (a b : LPBackend) : Bool :=
  a.defaultPriority < b.defaultPriority ||
    (a.defaultPriority == b.defaultPriority && a.name < b.name)

end LPBackend

end LP
