---
description: How a rule is written here — what may go in a list item, what belongs in prose, and the provenance every rule declares.
paths: [".claude/rules/**", "claude/.claude/rules/**"]
proved-by: tests/rules-hygiene.test.sh
---

# Writing a rule

Adapted from the policy-layer rule of the cloudarr-workspace harness. That repo
settles provenance with ADRs and has none of them here, so the field is not
copied: this repo's currency is the measurement, and `proved-by:` names it.

## Declare `proved-by:` in the frontmatter

Closed vocabulary. `tests/rules-hygiene.test.sh` rejects anything else, and
rejects a path that does not exist.

| Term | Means |
|---|---|
| `tests/<file>` | a suite fails when the norm is broken |
| `README.md § <section>` · `docs/<file>.md` | a recorded measurement backs it, no guard — **DEBT**, and it counts |
| `none` | nothing behind it yet — **DEBT**, and it counts |
| `not-applicable` | the violation leaves no trace a machine could read |

The link is written **once**, here. The other direction is derived, not stored:

```bash
git grep -l 'rules-hygiene' .claude/rules/   # which rules lean on this test?
```

Two edges for one fact means two copies to keep honest. With one source, the
disagreement stops being possible instead of being detected.

- **A norm nobody measured is orphan.** Either it declares `none` and counts as
  debt, or it goes back and gets measured. It never arrives silently.
- **Changing HOW a norm is enforced needs no new measurement.** Changing WHAT
  the norm says does.

## What may go in a list item

- **Only what can be DISOBEYED.** `zsh` reading `.zshrc` before `.zprofile` is
  not a norm, it is how zsh works. Fact, behaviour and history go to the
  **prose**; the list is norm only.
- **Every item names WHEN and WHAT** — a trigger you can recognise mid-task and
  a concrete act. *"Check the name on disk before you claim it"* holds; *"do not
  mistake the map for the territory"* is a maxim, and a maxim does not hold.
- **A line you are copying into a second rule file is probably a fact.** Norm
  does not duplicate that way; description does. Move it to prose.

A rule that cannot be disobeyed still takes a slot, dilutes the list, and
teaches the reader to skim — and the reader is an agent. The cost is not the
line, it is the adherence of the rules next to it, which do have teeth.

## Ceiling: 200 lines

The reason is not taste. A long file eats context and lowers adherence.

## Verification

```bash
./tests/rules-hygiene.test.sh
```
