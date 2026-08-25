#!/usr/bin/env bash
# SessionStart. Cannot block anything; its whole job is to put the state of the
# live checkout in front of the agent at turn zero, instead of at the turn
# where it starts mattering.
# shellcheck source=.claude/hooks/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

state="$(checkout_state)"
branch="$(git -C "$DOTFILES_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || echo '(detached)')"

printf 'dotfiles: %s checkout on %s' "$state" "$branch"
[ "$state" = stowed ] && [ "$branch" != main ] \
  && printf ' — THE LIVE CONFIG IS ON A BRANCH. Put it back: git switch main'

n="$(git -C "$DOTFILES_DIR" worktree list --porcelain 2>/dev/null | grep -c '^worktree ' || true)"
[ "${n:-1}" -gt 1 ] && printf ' | %s worktree(s) open, list them with: git wt list' "$((n - 1))"
printf '\n'
exit 0
