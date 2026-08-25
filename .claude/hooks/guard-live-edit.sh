#!/usr/bin/env bash
# PreToolUse on Edit|Write. Refuses to edit a stow package inside the STOWED
# checkout, because ~/.zshrc and friends are symlinks into it: the file is live
# the instant it is saved, before any git command runs.
#
# This is the guard that was missing. The siren, install.sh's refusal and the
# git-switch rule all watch git operations — and on 2026-08-25 the whole day's
# work went straight onto the live tree by editing, with no git operation
# involved and nothing to stop it.
# shellcheck source=.claude/hooks/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# In a linked worktree nothing under $HOME points here — editing is the point.
[ "$(checkout_state)" = stowed ] || allow

path="$(hook_field '.tool_input.file_path')"
[ -n "$path" ] || allow

# package_of() lives in lib.sh because guard-live-write.sh needs the identical
# answer for a target it dug out of a shell command. One definition, so the two
# guards cannot come to disagree about what counts as live.
pkg="$(package_of "$path")"
[ -n "$pkg" ] || allow

deny "$path is inside the '$pkg' stow package, and this checkout is the one \$HOME points at — the file goes live the moment it is written, before any git command runs.

Do it in a worktree instead:
    git wt new <branch>
then edit it under ../dotfiles-wt/<branch>/, and when it is ready:
    git wt promote <branch>

If it could affect shell latency, measure it there first:
    ./measure/compare.sh ../dotfiles-wt/<branch>"
