#!/usr/bin/env bash
# Runs every property test. Exits non-zero if any property regressed.
#
# Run this after changing anything, and after `./install.sh` on a new machine.
# Green here means: your shell will not make an AI CLI agent waste a turn in
# any of the ways this repo knows about.
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR

failed=0
total=0
for t in "$DOTFILES_DIR"/tests/*.test.sh; do
  [ -e "$t" ] || continue
  total=$((total + 1))
  if ! "$t"; then failed=$((failed + 1)); fi
  echo
done

if [ "$total" -eq 0 ]; then
  printf '\033[31mERROR\033[0m  no test files found in tests/ — nothing was verified.\n'
  exit 1
fi

# Which checkout is this? In a linked worktree the live-config checks did not
# run, and "all N suites passed" must not be allowed to read as "everything was
# checked". Sourced directly rather than through tests/lib.sh: lib.sh creates a
# mktemp directory that only summary() removes, and verify.sh never calls it.
# shellcheck source=tests/checkout-state.sh
. "$DOTFILES_DIR/tests/checkout-state.sh"
state="$(checkout_state)"

if [ "$failed" -eq 0 ]; then
  if [ "$state" = stowed ]; then
    printf '\033[32m▪ all %d suites passed\033[0m\n' "$total"
  else
    printf '\033[32m▪ all %d suites passed\033[0m \033[33m(%s checkout — the live-config checks did not run)\033[0m\n' \
           "$total" "$state"
  fi
else
  printf '\033[31m▪ %d of %d suites failed\033[0m\n' "$failed" "$total"
  exit 1
fi
