#!/usr/bin/env bash
# PROPERTY: every number this repo publishes can be taken again, on this
#           machine, by the person reading it.
#
# WHY THIS MATTERS
#   This is a different question from tests/deps-installed.test.sh, and the
#   difference is the whole reason this suite exists.
#
#     A DEPENDENCY is a tool the CONFIG needs. Without `stow`, install breaks.
#     Something fails loudly and you go fix it.
#
#     An INSTRUMENT is a tool a CLAIM needs. Without `zsh-bench`, nothing
#     breaks — README § Prompt choice simply becomes a table of numbers nobody
#     present can reproduce. It fails silently, and it reads as evidence.
#
#   Found on 2026-08-25, by an agent asked to measure a config change and
#   discovering it could not: README cites "Measured with zsh-bench, 2 runs ×
#   16 iterations", the Brewfile mentions the tool only inside a comment on
#   `tmux`, and zsh-bench was not installed. There is no brew formula for it,
#   so `brew bundle` could never have caught this and deps-installed could
#   never have looked.
#
#   `.claude/rules/signals.md` is explicit: an unchecked number is worse than
#   no number, because it carries the authority of evidence without the
#   backing. A number whose instrument is absent is exactly that. This suite is
#   how that rule stops depending on someone noticing.
#
#   MISSING IS A FAILURE HERE, NOT A SKIP. A skip would let a new measured
#   claim ship with no instrument behind it and keep the suite green, which is
#   the rot this file exists to prevent. The fix is one command and the failure
#   message names it.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "▸ the instruments behind the numbers"

cd "$DOTFILES_DIR" || { bad "cannot enter repo"; summary; exit 1; }

INSTRUMENTS_DIR="$DOTFILES_DIR/.instruments"
MAIN_WT="$(main_worktree_path)"; [ -n "$MAIN_WT" ] || MAIN_WT="$DOTFILES_DIR"

# instrument_probe <name> -> prints "<kind>:<target>|<claim it backs>", or
# nothing when this suite does not know the tool. Always exits 0.
#
# The unknown case is handled by the CALLER as a failure, the same device
# deps-installed.test.sh uses: naming a new instrument in a doc without
# teaching this suite to see it turns the suite red instead of leaving a claim
# unbacked in silence.
instrument_probe() {
  case "$1" in
    zsh-bench) printf 'file:%s/zsh-bench/zsh-bench|README.md § Prompt choice\n' "$INSTRUMENTS_DIR" ;;
    python3)   printf 'bin:python3|measure/analyze.py, and every number derived from it\n' ;;
    *)         : ;;
  esac
}

# --- 1. every instrument a doc names must be one this suite knows ----------
# Parsed from the documents, not from a list kept here: a list kept here would
# be a second copy of the same fact, and policy-layer.md says the disagreement
# should be impossible rather than detected.
named=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  named=$((named + 1))
  if [ -n "$(instrument_probe "$name")" ]; then
    ok "'$name' is a named instrument this suite knows"
  else
    bad "'$name' is a named instrument this suite knows" \
        "a doc says \"Measured with $name\" and tests/instruments.test.sh cannot see it — add a case to instrument_probe"
  fi
done < <(grep -ho 'Measured with \[`[^`]*`\]' README.md docs/*.md CLAUDE.md 2>/dev/null \
         | sed 's/.*\[`//; s/`\].*//' | sort -u)

# A regex that matches nothing reports a clean sweep of zero claims. This repo
# has at least one measured claim and will not lose it silently.
if [ "$named" -ge 1 ]; then
  ok "the docs' measurement attributions were found and read ($named)"
else
  bad "the docs' measurement attributions were found and read" \
      "no \"Measured with [\`tool\`]\" line matched — either the docs changed shape or this grep rotted"
fi

# --- 2. every instrument is actually here ---------------------------------
for name in zsh-bench python3; do
  entry="$(instrument_probe "$name")"
  probe="${entry%%|*}"; claim="${entry#*|}"
  target="${probe#*:}"
  present=1
  case "$probe" in
    bin:*)  command -v "$target" >/dev/null 2>&1 || present=0 ;;
    file:*) [ -x "$target" ] || present=0 ;;
  esac
  if [ "$present" -eq 1 ]; then
    ok "$name is present — '$claim' can be reproduced"
  else
    bad "$name is present — '$claim' can be reproduced" \
        "absent, so that claim currently has no backing on this machine — run: ./measure/bootstrap.sh"
  fi
done

# --- 3. the instrument directory must never be published ------------------
# It holds a clone of someone else's repository. Committing it would vendor a
# third party into this one and put its history inside these numbers.
if [ -d "$INSTRUMENTS_DIR" ]; then
  if git check-ignore -q .instruments 2>/dev/null; then
    ok ".instruments/ is gitignored"
  else
    bad ".instruments/ is gitignored" "it holds a clone of another repository and must not ship"
  fi
else
  skip ".instruments/ is gitignored" "the directory does not exist yet — run: ./measure/bootstrap.sh"
fi

# --- 4. the slow lane's entry point, checked in the fast lane --------------
# measure/compare.sh cannot be exercised here — one run takes about a minute
# and varies, which is the whole reason .claude/rules/tests.md puts it in the
# other lane. What CAN be asserted cheaply is that it refuses the inputs that
# would produce a meaningless number, and every one of these refusals happens
# before a single benchmark starts.
CMP="$DOTFILES_DIR/measure/compare.sh"
assert_rc "measure/compare.sh is executable" 0 test -x "$CMP"

# Comparing the live checkout against itself would print a table of pure noise
# dressed as a result.
assert_fails "compare.sh refuses the main checkout as a candidate" "$CMP" "$MAIN_WT"

# A directory that is not a checkout has no zsh/.zshrc, so ZDOTDIR would fall
# through to an empty config and the arm would measure a shell nobody has.
assert_fails "compare.sh refuses a directory that is not a checkout" "$CMP" /tmp

# No argument must not silently mean "compare against something".
assert_fails "compare.sh refuses to run with no candidate" "$CMP"

summary
