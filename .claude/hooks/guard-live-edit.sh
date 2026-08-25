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

case "$path" in
  /*) abs="$path" ;;
  *)  abs="$DOTFILES_DIR/$path" ;;
esac
case "$abs" in
  "$DOTFILES_DIR"/*) rel="${abs#"$DOTFILES_DIR"/}" ;;
  *) allow ;;                       # not this repo at all
esac

pkg="${rel%%/*}"
[ "$pkg" != "$rel" ] || allow       # a file at the repo root is not a package

hit=0
while IFS= read -r p; do
  [ "$p" = "$pkg" ] && hit=1
done <<EOF
$(stow_packages)
EOF
[ "$hit" -eq 1 ] || allow

deny "$rel is inside the '$pkg' stow package, and this checkout is the one \$HOME points at — the file goes live the moment it is written, before any git command runs.

Do it in a worktree instead:
    git wt new <branch>
then edit ../dotfiles-wt/<branch>/$rel, and when it is ready:
    git wt promote <branch>

If it could affect shell latency, measure it there first:
    ./measure/compare.sh ../dotfiles-wt/<branch>"
