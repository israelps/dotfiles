---
description: Validate a signal against controls that already have known answers before it decides anything, and publish its blind spot next to its number.
proved-by: not-applicable
---

# Trusting a signal

Always loaded, no `paths:`. Every other rule here rests on a measurement, so the
way a measurement earns trust is upstream of all of them. An unchecked number is
worse than no number: it carries the authority of evidence without the backing.

No test can catch a violation — nothing on disk shows that you believed a signal
you never checked. Hence `not-applicable`, and hence prose that stays loaded.

## Before the signal decides anything

- **Run it against at least two controls whose answer you already know, chosen
  to differ in kind.** Same kind twice is one control. A file-usage probe needs a
  compiled binary *and* an interpreted script; a history counter needs a command
  you type constantly *and* one that only ever runs from a script.
- **A control that disagrees kills the signal.** Do not widen a tolerance until
  the control passes — that fits the signal to the answer you wanted.
- **When you report the number, report what it cannot see, in the same breath.**
  A count with no stated blind spot reads as complete.
- **Say which cases you validated, never that "it works".** One probe is a probe.

## Measured here

Two failures on 2026-08-21, both caught by controls, neither by inspection:

**`atime` as "last used".** It updated when `eza` ran, so it looked like a
per-binary usage signal. Against a control it failed: `stow` had just been
executed and its `atime` had not moved. `eza` is a Mach-O binary, `stow` is a
Perl script — a signal right in one case and wrong in the other, about to decide
what got uninstalled. Dropped, not tuned.

**A history counter reading `libexec/`.** `awscli` and `python@3.14` both came
back `173x` — an identical count is not a coincidence, it is one number being
read twice. `awscli` ships an internal venv whose `libexec/bin` holds a
`python3`, and the counter had attributed python's usage to it. Restricted to
`bin/` and `sbin/`, `awscli` fell to the 35 uses of its own `aws`.

The control that exposed both was the same and it costs nothing: run the signal
over tools whose answer you already know, and look at whether it agrees.
