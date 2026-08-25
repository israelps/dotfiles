#!/usr/bin/env bash
# Stop. Refuses to let the turn end with the live checkout parked on a branch.
# CLAUDE.md invariant 6 says "leave the repo on main"; until now that was prose
# and prose is what gets skimmed.
#
# IT BLOCKS AT MOST ONCE PER SESSION. A Stop hook that keeps refusing is a trap
# with no exit: the agent cannot always fix what it is blocked on, and the
# owner is left hammering the same wall. One refusal delivers the message; a
# second would only be punishment.
# shellcheck source=.claude/hooks/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ "$(checkout_state)" = stowed ] || allow

branch="$(git -C "$DOTFILES_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || echo main)"
[ "$branch" = main ] && allow

sid="$(hook_field '.session_id')"; [ -n "$sid" ] || sid=unknown
marker="${TMPDIR:-/tmp}/dotfiles-stopguard-$sid"
[ -e "$marker" ] && allow
: > "$marker"

printf 'The live checkout is still on '\''%s'\''. $HOME resolves into it, so the next
shell — including the next agent session — gets this branch. Put it back with:
    git switch main
(This blocks once per session; stopping again will go through.)\n' "$branch" >&2
exit 2
