# LPCore

[![Lean](https://img.shields.io/badge/Lean-4.31.0--rc1-blue.svg)](./lean-toolchain)
[![License](https://img.shields.io/github/license/kim-em/lp-core.svg)](./LICENSE)

The shared LP type vocabulary and backend abstraction every package
in the [`kim-em/soplex`](https://github.com/kim-em/soplex) family
agrees on. Pure Lean, no native dependencies, no `moreLinkArgs`.

This repository defines `Problem`, `Options`, `Solution`,
`Certificate`, `SolveError` (the data) plus the `LPBackend` record
(the abstraction concrete solvers implement). It is consumed by:

* [`kim-em/soplex-ffi`](https://github.com/kim-em/soplex-ffi) — marshals the data across the C++ boundary,
* [`kim-em/lp-verify`](https://github.com/kim-em/lp-verify) — checks certificates against the same `Problem`,
* [`kim-em/lp-tactic`](https://github.com/kim-em/lp-tactic) — drives the `by lp` tactic and owns the backend registry,
* `kim-em/lp-backend-*` — every concrete backend produces an `LPBackend`,
* [`kim-em/soplex`](https://github.com/kim-em/soplex) — the meta-package; `import Soplex` is the front door.

If you just want `by lp` end-to-end, depend on `kim-em/soplex`.
Depend on `lp-core` directly only when you are writing another
package in this family (a new backend, a verifier variant, a
serialiser, etc.).

## Quickstart

Add `LPCore` to your `lakefile.lean`:

```lean
require LPCore from git "https://github.com/kim-em/lp-core" @ "main"
```

A `Problem` with two variables, two constraints, and a maximise
objective looks like this:

```lean
import LPCore
open Soplex

def lp : Problem 2 2 :=
  { c         := #v[3, 5]
    a         := #[(0, 0, 1), (0, 1, 0), (1, 0, 3), (1, 1, 2)]
    rowBounds := #v[(none, some 4), (none, some 18)]
    colBounds := #v[(some 0, none), (some 0, none)] }

def opts : Options := { sense := .maximize }

-- Validate normalises the sparse matrix and rejects malformed input.
example : Except ProblemError (Problem 2 2) := validate lp
```

`LPCore` does not solve LPs on its own — it provides the data
contract. To actually solve, pull in a backend (e.g. the FFI
backend bundled with `kim-em/soplex`) or write your own
implementing `LPBackend`.

## Trust model

Pure Lean. The verifier ([`kim-em/lp-verify`](https://github.com/kim-em/lp-verify))
treats `Problem` and `Certificate` as opaque inputs and validates
the certificate's mathematical claims before constructing any proof.
This package adds no trust assumptions of its own.

## Layout

```
LPCore.lean              # top-level import (re-exports the three modules)
LPCore/Types.lean        # Problem, Options, Solution, Certificate, SolveError, enums
LPCore/Validate.lean     # validate, validateOptions, validateRaw
LPCore/Backend.lean      # the LPBackend record + lt comparator
```

All declarations live in `namespace Soplex` (and `namespace Soplex.LP`
for `LPBackend`). The namespace is shared across this family of
packages; consumers refer to `Soplex.Problem`, `Soplex.Options`,
etc. regardless of which package they imported the type from.

## Licence

`LPCore` is licensed under the [Apache License 2.0](./LICENSE),
matching the rest of the `kim-em/soplex` family and SoPlex
itself.
