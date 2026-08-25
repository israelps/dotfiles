#!/usr/bin/env bash
# SessionStart. Cannot block anything. Two jobs, both about turn zero: put the
# state of the live checkout in front of the agent before it starts mattering,
# and record what that state WAS so guard-live-drift.sh can tell the agent's
# changes from the owner's. Whatever is already dirty here is the owner's, by
# definition — the session has not done anything yet.
# shellcheck source=.claude/hooks/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# The baseline first: a report nobody reads is survivable, a missing baseline
# makes the net either blind or accusatory. Failure is non-fatal by design —
# guard-live-drift.sh adopts a floor of its own and says so on stderr.
if [ "$(checkout_state)" = stowed ]; then
  dirty_packages > "$(drift_baseline "$(hook_field '.session_id')")" 2>/dev/null || true
fi

state="$(checkout_state)"
branch="$(git -C "$DOTFILES_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || echo '(detached)')"

printf 'dotfiles: %s checkout on %s' "$state" "$branch"
[ "$state" = stowed ] && [ "$branch" != main ] \
  && printf ' — THE LIVE CONFIG IS ON A BRANCH. Put it back: git switch main'

n="$(git -C "$DOTFILES_DIR" worktree list --porcelain 2>/dev/null | grep -c '^worktree ' || true)"
[ "${n:-1}" -gt 1 ] && printf ' | %s worktree(s) open, list them with: git wt list' "$((n - 1))"
printf '\n'
exit 0
