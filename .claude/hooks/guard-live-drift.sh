#!/usr/bin/env bash
# PostToolUse. The net under the three PreToolUse guards: it asks git whether
# the live surface actually moved, rather than asking a command what it intends.
#
# WHY A NET IS NEEDED AT ALL
#   guard-live-edit.sh reads a file_path and guard-live-write.sh reads a command.
#   Both are exact about what they can see, and both are blind to the same
#   things: an edit hosted by an interpreter (`python3 -c`, `perl -i`), a path
#   built at runtime from a variable, a path inside a script invoked by name.
#   No amount of parsing closes that; a different question does. `git status`
#   does not care how the bytes arrived.
#
# WHY IT COMPARES AGAINST A BASELINE INSTEAD OF JUST "IS IT DIRTY"
#   The owner's own uncommitted work in a package is none of this hook's
#   business — firing on it would blame the agent for the owner's edit, and a
#   guard that accuses wrongly is a guard that gets turned off. So
#   session-start.sh snapshots the surface at turn zero and this compares
#   against that: the question is only ever "did THIS session move it".
#
# WHY IT DOES NOT NAG
#   After reporting, it rewrites the baseline. Each new drift is reported once
#   and then becomes the accepted floor, so work can continue. A PostToolUse
#   hook that keeps blocking is the trap guard-stop.sh's comment warns about,
#   with the added cruelty of firing on every subsequent tool call.
#
# WHAT IT COSTS, AND WHAT IT CANNOT UNDO
#   One `git status` on five paths per write-capable tool call. And it is late
#   by construction: the file was live for the span of one tool call. .zshrc
#   only matters to the next shell, but starship and ssh re-read per invocation,
#   so for those the wrong config was briefly the real one. Late and complete
#   beats early and partial only in combination — which is why the PreToolUse
#   guards stay.
# shellcheck source=.claude/hooks/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# In a linked worktree nothing under $HOME points here — drift is the point.
[ "$(checkout_state)" = stowed ] || allow

baseline="$(drift_baseline "$(hook_field '.session_id')")"
[ -n "$baseline" ] \
  || fail_open "no session_id in the payload — cannot tell this session's changes from another's"

current="$(dirty_packages)"

# No baseline means the earliest hook of this session has not run (or TMPDIR was
# cleared underneath it). Adopt the current state as the floor rather than
# reading every pre-existing change as this session's doing, and say so once —
# a silent adoption here would look exactly like a clean session.
if [ ! -e "$baseline" ]; then
  printf '%s\n' "$current" > "$baseline" 2>/dev/null \
    || fail_open "cannot write the drift baseline at $baseline"
  printf 'hook %s: no baseline for this session — adopting the current live surface as the floor\n' \
    "${0##*/}" >&2
  exit 0
fi

drift="$(LC_ALL=C comm -13 "$baseline" <(printf '%s\n' "$current") | sed '/^$/d')"
[ -n "$drift" ] || allow

# Report once, then accept. The next call is not blocked for the same file.
printf '%s\n' "$current" > "$baseline" 2>/dev/null || true

block "The live surface moved during this session, and none of the PreToolUse guards
saw it happen:

$drift

These paths are inside stow packages on the checkout \$HOME points at, so they
are the running configuration now — starship and ssh re-read their config on
every invocation, and .zshrc lands on the next shell, including the next agent
session.

Put the machine back, then redo the work where it belongs:
    git -C $DOTFILES_DIR restore <the paths above>
    git wt new <branch>

If the change was deliberate and you want to keep it, say so and move it into a
worktree with 'git wt new <branch>' — this is reported once, so the next call
will go through either way."
