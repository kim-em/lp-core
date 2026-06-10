/-
  Behavioral tests for the `LPCore` validators: `normaliseSparse`,
  `collapseSorted`, `validate`, `validateRaw`, and `validateOptions`.

  Also compiles the README quickstart `Problem` verbatim, so the
  first snippet a reader copies cannot drift from the API.

  Run via `lake test` (the `validate-tests` executable).
-/

import LPCore

open LP

namespace LPCoreTest.Validate

private def assertM (cond : Bool) (msg : String) : IO Unit := do
  unless cond do throw (IO.userError msg)

/-- The README quickstart example, verbatim (compile check). -/
def readmeLp : Problem 2 2 :=
  { c         := #v[3, 5]
    a         := #[(0, 0, 1), (0, 1, 0), (1, 0, 3), (1, 1, 2)]
    rowBounds := #v[(none, some 4), (none, some 18)]
    colBounds := #v[(some 0, none), (some 0, none)] }

/-- `normaliseSparse` sorts by `(row, col)`, sums duplicates, and
    drops zero-valued results. -/
def case_normaliseSparse : IO Unit := do
  let a : Array (Fin 2 × Fin 2 × Rat) :=
    #[(1, 1, 2), (0, 0, 1), (0, 0, 2), (1, 0, 0)]
  let out := normaliseSparse a
  assertM (out == #[(0, 0, 3), (1, 1, 2)])
    s!"normaliseSparse: unexpected output {repr out}"

/-- Duplicate entries that cancel to zero are dropped entirely. -/
def case_collapseCancel : IO Unit := do
  let a : Array (Fin 2 × Fin 2 × Rat) := #[(0, 0, 1), (0, 0, -1)]
  let out := collapseSorted a
  assertM out.isEmpty s!"collapseSorted: expected empty, got {repr out}"

/-- Empty input stays empty. -/
def case_collapseEmpty : IO Unit := do
  let out := collapseSorted (#[] : Array (Fin 2 × Fin 2 × Rat))
  assertM out.isEmpty s!"collapseSorted: expected empty, got {repr out}"

/-- `validate` accepts the README problem and prunes its zero entry. -/
def case_validateAccepts : IO Unit := do
  match validate readmeLp with
  | .ok p =>
    assertM (p.a == #[(0, 0, 1), (1, 0, 3), (1, 1, 2)])
      s!"validate: unexpected normalised matrix {repr p.a}"
  | .error e => throw (IO.userError s!"validate: rejected README problem: {repr e}")

/-- `validate` rejects an inverted column bound. -/
def case_validateColInversion : IO Unit := do
  let p : Problem 1 1 :=
    { c := #v[1], a := #[], rowBounds := #v[(none, none)]
      colBounds := #v[(some 2, some 1)] }
  match validate p with
  | .error (.boundInverted ..) => pure ()
  | r => throw (IO.userError s!"validate: expected boundInverted, got {repr (r.map (·.a))}")

/-- `validate` rejects an inverted row bound. -/
def case_validateRowInversion : IO Unit := do
  let p : Problem 1 1 :=
    { c := #v[1], a := #[], rowBounds := #v[(some 1, some 0)]
      colBounds := #v[(none, none)] }
  match validate p with
  | .error (.boundInverted ..) => pure ()
  | r => throw (IO.userError s!"validate: expected boundInverted, got {repr (r.map (·.a))}")

/-- `validateRaw` rejects out-of-range sparse indices. -/
def case_validateRawOutOfRange : IO Unit := do
  let p : RawProblem 1 1 :=
    { c := #v[1], a := #[(5, 0, 1)], rowBounds := #v[(none, none)]
      colBounds := #v[(none, none)] }
  match validateRaw p with
  | .error (.indexOutOfRange ..) => pure ()
  | r => throw (IO.userError s!"validateRaw: expected indexOutOfRange, got {repr (r.map (·.a))}")

/-- `validateOptions` rejects bad limits and accepts the defaults. -/
def case_validateOptions : IO Unit := do
  match validateOptions { iterLimit := some 0 } with
  | .error .zeroIterLimit => pure ()
  | _ => throw (IO.userError "validateOptions: expected zeroIterLimit")
  match validateOptions { timeLimit := some (-1.0) } with
  | .error (.negativeTimeLimit _) => pure ()
  | _ => throw (IO.userError "validateOptions: expected negativeTimeLimit")
  match validateOptions { timeLimit := some (0.0 / 0.0) } with
  | .error .nanTimeLimit => pure ()
  | _ => throw (IO.userError "validateOptions: expected nanTimeLimit")
  match validateOptions { iterLimit := some (ffiMaxInt + 1) } with
  | .error (.iterLimitTooLarge ..) => pure ()
  | _ => throw (IO.userError "validateOptions: expected iterLimitTooLarge")
  match validateOptions {} with
  | .ok _ => pure ()
  | .error e => throw (IO.userError s!"validateOptions: rejected defaults: {repr e}")

def main : IO UInt32 := do
  case_normaliseSparse
  case_collapseCancel
  case_collapseEmpty
  case_validateAccepts
  case_validateColInversion
  case_validateRowInversion
  case_validateRawOutOfRange
  case_validateOptions
  IO.println "lp-core validate tests: all passed"
  return 0

end LPCoreTest.Validate

def main : IO UInt32 := LPCoreTest.Validate.main
