---
description: How a property test is written here — state the invariant, prove it cannot pass vacuously, and stay on macOS bash 3.2.
paths: ["tests/**", "verify.sh"]
proved-by: tests/lib.sh
---

# Writing a property test

Loaded only when you touch `tests/` or `verify.sh`.

## A test states a property, not a command

Name the invariant, then assert it. Every file here opens with **WHY THIS
MATTERS** and the measurement that justified the fix — a test whose reason is
lost is a test nobody dares delete and nobody understands.

## Non-vacuity is the whole point

A check that silently matches nothing reports green for the wrong reason, which
is worse than no test.

- `lib.sh` traps `ERR`: any unexpected shell error fails the run. Verified by
  injecting a `mapfile` call, which macOS's bash 3.2 does not have.
- `summary` fails when zero assertions ran.
- `verify.sh` fails when `tests/` is empty.

**Everything here must run on the bash that ships with macOS (3.2).** No
`mapfile`, no associative arrays, no `${var^^}`.

## Assert the property, not the implementation

`assert_fails` checks for non-zero, not for a specific code: `ls` on a missing
path exits 1 on BSD and 2 on GNU/eza. Pinning the number asserts the tool, not
the behaviour.

## Two traps worth knowing

`if ! cmd; then rc=$?; fi` always yields 0 — `$?` there is the status already
inverted by `!`. Use `cmd || rc=$?`, which is also a condition context and so
does not trip the `ERR` trap.

Never point `ZDOTDIR` at the repo: zsh writes `.zcompdump` into it and the
suite litters the repository. `lib.sh` builds a temporary one.

## Tests must not need the network

`ssh-multiplex.test.sh` checks configuration, never a live host. A test that
needs the network fails for reasons that have nothing to do with the property.
