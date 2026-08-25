#!/usr/bin/env bash
# PreToolUse on Bash. Refuses the git operations that REPLACE the working
# tree's contents in the stowed checkout. There is no pre-checkout hook in git,
# so .githooks/post-checkout can only warn after the fact; this refuses before.
#
# What it covers that the siren cannot: git stash, git reset --hard. Those
# change the live config and fire no git hook at all.
# shellcheck source=.claude/hooks/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ "$(checkout_state)" = stowed ] || allow

cmd="$(hook_field '.tool_input.command')"
[ -n "$cmd" ] || allow

# Only judge commands aimed at THIS repository. A git command run elsewhere in
# the same session is none of this guard's business.
case "$cmd" in
  *dotfiles-wt*) allow ;;           # aimed at a worktree, which is the point
esac

want=""
case "$cmd" in
  *"git switch main"*|*"git checkout main"*) allow ;;   # the cure, always
  *"git switch "*|*"git checkout -b"*|*"git checkout "[a-zA-Z]*)
      want="leaves main, so \$HOME starts resolving to another branch's files" ;;
  *"git stash"*)
      want="replaces the working tree with the stash's contents" ;;
  *"git reset --hard"*)
      want="overwrites the working tree, and fires no git hook at all" ;;
esac
[ -n "$want" ] || allow

# `git checkout -- <path>` restores a file rather than moving branches. It is
# still a live overwrite, but refusing it would block ordinary recovery.
case "$cmd" in *"git checkout --"*) allow ;; esac

deny "That command $want — and this checkout is the one \$HOME points at.
starship and ssh re-read their config on every invocation, so they change
immediately; .zshrc lands on the next shell, including the next agent session.

Work on a branch without touching this machine:
    git wt new <branch>

If you meant to put the machine back, that one is always allowed:
    git switch main"
