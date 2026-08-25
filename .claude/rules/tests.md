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

## Two lanes: properties and measurements

`verify.sh` is the fast lane and its contract is "run this before proposing any
change". A property is boolean, deterministic and cheap. A measurement is none
of those: `zsh-bench` takes tens of seconds and varies between runs. Putting one
in `verify.sh` breaks the contract that makes anyone run it at all.

Measured on 2026-08-25, on this machine, `zsh-bench -i 3`: three runs of the
same live config gave 252.965, 245.646 and 244.767 ms of `first_prompt_lag_ms`
— a spread of 8.2 ms, or 3.3%. The same config with a `sleep 0.4` injected gave
692.899 ms. So the instrument resolves ~400 ms cleanly and cannot see 10 ms at
all.

- **A check that is slow or varies between runs goes in `measure/`, never in
  `tests/`.** The trigger is the second time you watch a suite pause.
- **A reported delta carries the noise floor measured in the SAME run.** Two
  measurements of the baseline, taken now, on this machine — never a number
  remembered from another day. A delta smaller than that floor is reported as
  "no detectable change", never as a figure.
- **An instrument is pinned to a commit before it decides anything.**
  `measure/bootstrap.sh` pins `zsh-bench`. A benchmark that moves under you
  turns two dated numbers into a comparison that never existed.

`tests/instruments.test.sh` is the fast-lane half of this: it asserts the
instruments are *present*, which is boolean and cheap. Whether they are
*correct* is the slow lane's job, and it is re-established on every run rather
than trusted.

## Tests must not need the network

`ssh-multiplex.test.sh` checks configuration, never a live host. A test that
needs the network fails for reasons that have nothing to do with the property.
