#!/usr/bin/env bash
# Minimal assertion helpers shared by every test.
#
# Design rule: a test must PROVE it ran. A check that silently matches nothing
# is worse than no check — it reports green for the wrong reason.
set -uo pipefail

# Any unexpected shell error must FAIL the suite. Without this, a typo or a
# missing builtin (bash 3.2 on macOS has no `mapfile`) prints an error to
# stderr and the suite still reports green — a vacuous pass, which is worse
# than no test at all. Caught exactly that way while writing this file.
_unexpected=0
trap '_unexpected=1' ERR

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ZSHRC="$DOTFILES_DIR/zsh/.zshrc"

_pass=0; _fail=0
RED=$'\033[31m'; GREEN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'

ok()   { _pass=$((_pass+1)); printf '  %sPASS%s  %s\n' "$GREEN" "$OFF" "$1"; }
bad()  { _fail=$((_fail+1)); printf '  %sFAIL%s  %s\n' "$RED" "$OFF" "$1"
         [ $# -gt 1 ] && printf '        %s%s%s\n' "$DIM" "$2" "$OFF"; return 0; }

# assert_eq <description> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $2 | got: $3"; fi
}

# assert_rc <description> <expected_rc> <command...>
assert_rc() {
  local desc="$1" want="$2"; shift 2
  # `|| got=$?` on purpose, for two reasons at once:
  #   - it is a condition context, so the ERR trap does not fire on the
  #     intentional failures these helpers exist to check;
  #   - it preserves the REAL exit code. `if ! cmd; then got=$?; fi` does not:
  #     there `$?` is the status already inverted by `!`, so it is always 0.
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" = "$want" ]; then ok "$desc"; else bad "$desc" "expected rc=$want | got rc=$got | cmd: $*"; fi
}

# assert_fails <description> <command...>
# Asserts a NON-ZERO exit. Deliberately not a specific number: `ls` on a
# missing path is 1 on BSD and 2 on GNU/eza, and pinning the number would make
# the test assert the implementation instead of the property.
assert_fails() {
  local desc="$1"; shift
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" -ne 0 ]; then ok "$desc"; else bad "$desc" "expected non-zero | got rc=0 | cmd: $*"; fi
}

# Run a snippet in a NON-INTERACTIVE zsh that has sourced our .zshrc.
# This is the shape that matters: tools which capture your shell state (agents,
# CI, scripts) end up here, WITHOUT `i` in $-.
zsh_noninteractive() { zsh -f -c "source '$ZSHRC' >/dev/null 2>&1; $1" 2>/dev/null; }

# Run a snippet in an INTERACTIVE zsh using our .zshrc.
#
# ZDOTDIR points at a TEMPORARY directory holding a symlink to the real
# .zshrc — never at the repo itself. zsh writes .zcompdump into $ZDOTDIR, and
# pointing it at zsh/ made the suite litter the repository; install.sh's
# conflict check is what caught that.
#
# Created at load time, NOT inside the function: `ZDOTDIR="$(helper)"` runs the
# helper in a subshell, and an EXIT trap set there fires the instant the
# substitution ends — deleting the directory before zsh ever reads it. That bug
# showed up as rc=127 for `tree`, because with no .zshrc sourced the alias was
# gone and no real `tree` binary exists on the machine.
ZDOT_TMP="$(mktemp -d)"
ln -sf "$ZSHRC" "$ZDOT_TMP/.zshrc"
zsh_interactive() { ZDOTDIR="$ZDOT_TMP" zsh -i -c "$1" 2>/dev/null; }

summary() {
  rm -rf "$ZDOT_TMP"
  printf '\n  %d passed, %d failed\n' "$_pass" "$_fail"
  if [ "$_unexpected" -ne 0 ]; then
    printf '  %sERROR%s  an unexpected shell error occurred (see stderr above)\n' "$RED" "$OFF"
    return 1
  fi
  [ "$_fail" -eq 0 ] || return 1
  # Non-vacuity guard: a suite that asserted nothing is not a green suite.
  [ "$_pass" -gt 0 ] || { printf '  %sERROR%s  no assertions ran\n' "$RED" "$OFF"; return 1; }
}
