/-
  The shared LP vocabulary: `Problem`, `Options`, `Solution`,
  `Certificate`, `SolveError`, and supporting enums.

  This is pure-Lean data, no native dependencies. It is the single
  agreed-upon shape that every consumer in the `leanprover/lp`
  family understands:

  * the FFI binding (`leanprover/soplex-ffi`) marshals it across the C++
    boundary;
  * the verifier (`leanprover/lp-verify`) checks certificates against it;
  * the tactic (`leanprover/lp-tactic`) hands it to whichever `LPBackend`
    is chosen;
  * every backend (`leanprover/lp-backend-*`) consumes a `Problem` and
    produces a `Solution`.

  Declarations live in `namespace LP` so that downstream consumers
  refer to `LP.Problem`, `LP.Options`, etc. unambiguously
  regardless of which package they imported the type from.
-/

namespace LP

/-- Largest natural value this package passes through SoPlex APIs that
    take C++ `int` parameters. -/
def ffiMaxInt : Nat := 2147483647

/-- Objective sense. The verifier internally canonicalises everything
    to `.minimize`; `.maximize` is reduced by negating the objective. -/
inductive ObjSense | minimize | maximize
  deriving Repr, DecidableEq

/-- Which simplex variant to run. `.auto` lets SoPlex decide. -/
inductive Simplex  | primal | dual | auto
  deriving Repr, DecidableEq

/-- Solver / verifier configuration. -/
structure Options where
  sense          : ObjSense    := .minimize
  /-- Wall-clock limit in seconds; `none` = unlimited. -/
  timeLimit      : Option Float := none
  /-- Simplex-iteration limit; `none` = unlimited. -/
  iterLimit      : Option Nat   := none
  simplex        : Simplex     := .auto
  verbose        : Bool        := false
  randomSeed     : UInt32      := 0
  /-- Fall back to precision boosting on ill-conditioned LPs. -/
  precisionBoost : Bool        := true
  /-- Enable SoPlex's presolve. `solveVerified` forces this `false`
      internally so certificates describe the original normalised LP. -/
  presolve       : Bool        := true
  deriving Repr

/-- LP problem in canonical sparse form.

    Sparse `a` entries are `(row, col, value)`, with row and column
    indices carrying their bounds in the type. `validate` normalises
    this representation: duplicate `(row, col)` entries are summed, zero
    values are dropped, entries are sorted by `(row, col)`. The verifier
    always runs against the post-`validate` form. -/
structure Problem (numConstraints numVars : Nat) where
  /-- Objective coefficients (length = `numVars`). All zero ⇒ pure
      feasibility. -/
  c              : Vector Rat numVars
  /-- Optional constant added to the objective. -/
  objOffset      : Rat := 0
  /-- Sparse constraint matrix entries: `(row, col, value)`, 0-indexed.
      The `Fin` indices rule out out-of-range entries by construction.
      Normalised by `validate`. -/
  a              : Array (Fin numConstraints × Fin numVars × Rat)
  /-- Per-row bounds `(lo, hi)`; `none` = ±∞. Covers ≤, =, ≥, and
      ranged constraints uniformly. -/
  rowBounds      : Vector (Option Rat × Option Rat) numConstraints
  /-- Per-variable bounds `(lo, hi)`; `none` = ±∞. -/
  colBounds      : Vector (Option Rat × Option Rat) numVars
  deriving Repr

namespace Problem

/-- Literal-friendly sparse-entry constructor. Unlike Lean's modular
    `OfNat (Fin n)` instance, the default proof obligation rejects
    out-of-range numerals with `by decide`. Non-literal indices can pass
    an explicit proof such as `by omega`. -/
def entry {numConstraints numVars : Nat} (row col : Nat) (value : Rat)
    (hrow : row < numConstraints := by decide)
    (hcol : col < numVars := by decide) :
    Fin numConstraints × Fin numVars × Rat :=
  (⟨row, hrow⟩, ⟨col, hcol⟩, value)

end Problem

/-- Raw sparse problem shape for parser / FFI boundaries that still
    receive natural row and column indices from outside Lean. Use
    `validateRaw` to convert the sparse entries to `Fin` indices and
    then normalise the resulting `Problem`. -/
structure RawProblem (numConstraints numVars : Nat) where
  c              : Vector Rat numVars
  objOffset      : Rat := 0
  a              : Array (Nat × Nat × Rat)
  rowBounds      : Vector (Option Rat × Option Rat) numConstraints
  colBounds      : Vector (Option Rat × Option Rat) numVars
  deriving Repr

/-- Tag used by `ProblemError.indexOutOfRange` and `boundInverted`. -/
inductive IndexKind | row | col | sparseEntry
  deriving Repr, DecidableEq

/-- Problem-related reasons a solve request cannot proceed. Most
    variants describe malformed or unrepresentable input caught at
    the validation / boundary layer (`validate`, `validateRaw`,
    `Problem.ofRaw`). `unsupportedFeature` is the exception: it
    describes a well-formed problem that falls outside a particular
    backend's first-cut scope. Keeping both flavours in one type lets
    `SolveError.invalidProblem` carry either without overloading
    `SolveError.bridge`, so a dispatcher can distinguish "try a more
    capable backend" from "the bridge protocol is broken." -/
inductive ProblemError
  /-- An array field had the wrong length for the declared `numVars` /
      `numConstraints`. -/
  | wrongLength      (field : String) (expected got : Nat)
  /-- A field is too large for the FFI representation used by SoPlex. -/
  | tooLarge         (field : String) (max got : Nat)
  /-- A sparse-entry coordinate or bound array index pointed outside
      the declared dimensions. -/
  | indexOutOfRange  (kind : IndexKind) (index bound : Nat)
  /-- A bound pair had `lo > hi`. -/
  | boundInverted    (kind : IndexKind) (i : Nat) (lo hi : Rat)
  /-- The problem is well-formed but uses a feature the chosen
      backend does not yet implement (e.g. ranged constraints, free
      variables, or bound shapes the backend has not implemented).
      Backends surface this as `SolveError.invalidProblem
      (.unsupportedFeature msg)` so that a dispatcher can fall
      through to a more capable backend instead of treating the
      failure as a bridge-protocol breakdown. `msg` should name the
      unsupported feature. -/
  | unsupportedFeature (msg : String)
  deriving Repr

/-- Why `validateOptions` rejected an `Options`. -/
inductive OptionError
  | nanTimeLimit
  | negativeTimeLimit (value : Float)
  | zeroIterLimit
  | iterLimitTooLarge (max got : Nat)
  deriving Repr

/-- Canonical lower / upper split for dual multipliers.

    All four vectors are nonnegative and length-matched to the problem
    (`m` rows, `n` cols); a coordinate is zero whenever the matching
    bound is `none`. The *signed* dual would be `rowLower − rowUpper`
    (and similarly for columns), but storing the split is strictly more
    expressive for ranged constraints, where the dual objective genuinely
    depends on the decomposition. -/
structure DualBundle (m n : Nat) where
  /-- Multipliers for `rowLoᵢ ≤ (Ax)ᵢ` (one per row). -/
  rowLower : Vector Rat m
  /-- Multipliers for `(Ax)ᵢ ≤ rowHiᵢ` (one per row). -/
  rowUpper : Vector Rat m
  /-- Multipliers for `colLoⱼ ≤ xⱼ` (one per column). -/
  colLower : Vector Rat n
  /-- Multipliers for `xⱼ ≤ colHiⱼ` (one per column). -/
  colUpper : Vector Rat n
  deriving Repr, Inhabited

/-- Outcome bucket reported by `solveExact` / `solveVerified`. -/
inductive SolveStatus
  | optimal
  | infeasible
  | unbounded
  | timeLimit
  | iterLimit
  /-- Refinement + boosting both failed. -/
  | numericFailure
  /-- Set by the *checker*, not by SoPlex: the certificate's
      numerator-plus-denominator bit length exceeded `denomBudget`. -/
  | budgetExceeded
  | aborted
  deriving Repr, DecidableEq, Inhabited

/-- Certificate of the solve outcome.

    Which fields are required depends on `status`:

    * `optimal`     — `primal` and `dual`
    * `infeasible`  — `dual` (a Farkas multiplier)
    * `unbounded`   — `primal` (a feasible base point) and `ray`
    * anything else — none required

    The verifier checks the appropriate combination and accepts /
    rejects accordingly.

    Parameterised by `(m n : Nat)` — the constraint and variable
    counts — so the primal / ray vectors and the dual bundle all
    carry their expected lengths in the type. -/
structure Certificate (m n : Nat) where
  primal : Option (Vector Rat n)
  dual   : Option (DualBundle m n)
  ray    : Option (Vector Rat n)
  deriving Repr, Inhabited

/-- Exact-mode result. `Solution.objective` is always in the
    *caller's original sense* (including `objOffset`), never the
    internal min-canonical value.

    Parameterised by `(numConstraints numVars : Nat)` so the
    embedded `Certificate` is dimension-aware at the type level.
    The dimensions come from the `Problem` the `Solution` was
    produced from. -/
structure Solution (numConstraints numVars : Nat) where
  status         : SolveStatus
  /-- Exact for `status = optimal`; a hint otherwise. -/
  objective      : Option Rat
  certificate    : Certificate numConstraints numVars
  /-- Captured solver log; `""` when `Options.verbose = false`. -/
  log            : String
  deriving Repr, Inhabited

/-- Float-mode result. Kept distinct from `Solution` to prevent
    accidental feeding into the verifier: these rationals are exact
    representations of IEEE-754 doubles, not exact-mode certificates.

    Parameterised by `(numVars : Nat)` — only the primal vector
    needs a length tag. -/
structure FloatSolution (numVars : Nat) where
  status      : SolveStatus
  /-- Primal solution as exact rationals representing the doubles
      SoPlex computed. NOT certificate-grade. -/
  primalAsRat : Option (Vector Rat numVars)
  objective   : Option Float
  /-- Captured solver log; `""` when `Options.verbose = false`. -/
  log         : String
  deriving Repr, Inhabited

/-- Errors surfaced by a backend's `solveExact`. Problem-related
    failures are reported as `invalidProblem`: malformed inputs use
    the structural validation variants of `ProblemError`, while
    backend capability misses use `ProblemError.unsupportedFeature`.
    All unclassified C++ / SoPlex failures remain bridge errors;
    true bridge-invariant violations may still `panic`. Dispatchers
    should treat `invalidProblem (.unsupportedFeature _)` as a cue
    to try another backend, and `bridge _` as a protocol breakdown
    to abort. -/
inductive SolveError
  | invalidProblem (e : ProblemError)
  | invalidOptions (e : OptionError)
  /-- File parse error from `readMps` / `readLp`. -/
  | parseError     (path : String) (msg : String)
  /-- FFI-level failure that didn't `panic`. -/
  | bridge         (msg : String)
  deriving Repr

/-! ## Objective canonicalisation. -/

/-- Flip the objective in place. Identity on everything else. -/
def negateObjective {m n : Nat} (p : Problem m n) : Problem m n :=
  { p with c := p.c.map Neg.neg, objOffset := -p.objOffset }

/-- Reduce to minimisation form. -/
def canonicalize {m n : Nat} (sense : ObjSense) (p : Problem m n) : Problem m n :=
  match sense with
  | .minimize => p
  | .maximize => negateObjective p

end LP
