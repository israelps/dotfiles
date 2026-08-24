#!/usr/bin/env bash
# Branch work for a repository whose working tree is the live config.
#
# WHY THIS EXISTS
#   ~/.zshrc, ~/.config/starship.toml, ~/.config/ghostty/config and
#   ~/.ssh/config.d are stow symlinks into this checkout. `git switch` here does
#   not "change a branch", it reconfigures the machine: starship and ssh read
#   their config per invocation, so those are live immediately; .zshrc lands on
#   the next shell, including the next agent session. See CLAUDE.md invariant 6.
#
#   So branch work happens in a LINKED WORKTREE, where nothing under $HOME
#   points, and the main checkout never leaves main.
#
# Reached as `git wt <cmd>` — ./install.sh sets the --local alias.
#
# NEVER TRUST $PWD IN THIS FILE. A `!`-prefixed git alias runs from the top of
# the ACTIVE worktree, so `git wt` typed inside a worktree runs THAT BRANCH's
# copy of this script. Every path below is derived from --git-common-dir, which
# points at the main checkout from anywhere.
set -uo pipefail

info() { printf '  %s\n' "$*"; }
erro() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; }
note() { printf '\033[2m  %s\033[0m\n' "$*"; }

usage() {
  cat <<'EOF'
usage: git wt <command>

  new <branch>       create ../<repo>-wt/<branch> on a new branch off main
  list               every worktree, with dirty / merged / locked
  clean [--yes]      remove worktrees whose branch is merged; dry run by default
  promote <branch>   merge --ff-only into main, remove the worktree, verify

Only `list` runs from inside a linked worktree. Everything that mutates has to
run from the main checkout, because `git wt` executes the active branch's copy
of this script.
EOF
}

git rev-parse --git-dir >/dev/null 2>&1 || { erro "not a git repository"; exit 1; }

COMMON="$(git rev-parse --path-format=absolute --git-common-dir)"
GITDIR="$(git rev-parse --path-format=absolute --git-dir)"
MAIN="${COMMON%/.git}"
# /x/y/dotfiles -> /x/y/dotfiles-wt. Derived, not hardcoded, so a fork or a
# rename does not need this file edited.
WT_ROOT="$(dirname "$MAIN")/$(basename "$MAIN")-wt"

IN_MAIN=0
[ "$GITDIR" = "$COMMON" ] && IN_MAIN=1

require_main() {
  [ "$IN_MAIN" -eq 1 ] && return 0
  erro "'$1' must run from the main checkout, not a linked worktree"
  info "git wt runs the ACTIVE branch's copy of this script — from here that is"
  info "whatever this branch happens to say."
  info "run it from:  $MAIN"
  exit 1
}

# porcelain_field <record> <label> — one field out of one `worktree list` record.
# sed, not awk: the porcelain format does not quote, so a path containing a
# space survives `sed -n 's/^worktree //p'` and dies in `awk '{print $2}'`.
porcelain_field() { printf '%s\n' "$1" | sed -n "s/^$2 //p" | head -1; }
porcelain_has()   { printf '%s\n' "$1" | grep -q "^$2\$"; }

# is_dirty <path> — tracked modifications OR untracked files, which is exactly
# what `git worktree remove` itself refuses on.
is_dirty() {
  [ -d "$1" ] || return 1
  [ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]
}

is_merged() {
  git -C "$MAIN" branch --merged main --format='%(refname:short)' 2>/dev/null \
    | grep -qx "$1"
}

# A slashed branch name nests: ../dotfiles-wt/feat/x leaves feat/ behind, and
# removing the last worktree leaves dotfiles-wt/ itself. rmdir only ever
# succeeds on an empty directory, so this cannot take anything with it.
prune_empty_dirs() {
  local d
  d="$(dirname "$1")"
  while [ "$d" != "$WT_ROOT" ] && [ "$d" != "/" ] && [ -n "$d" ]; do
    rmdir "$d" 2>/dev/null || break
    d="$(dirname "$d")"
  done
  rmdir "$WT_ROOT" 2>/dev/null || true
}

# Walk every worktree record and call `handle_worktree` with the parsed fields.
# One parser, three commands: list, clean and promote all need the same facts.
for_each_worktree() {
  local rec="" line
  while IFS= read -r line; do
    if [ -n "$line" ]; then rec="$rec$line
"; continue; fi
    [ -n "$rec" ] && handle_worktree "$rec"
    rec=""
  done < <(git -C "$MAIN" worktree list --porcelain 2>/dev/null; printf '\n')
  [ -n "$rec" ] && handle_worktree "$rec"
  return 0
}

# ── new ─────────────────────────────────────────────────────────────────────
cmd_new() {
  local branch="${1:-}" path
  [ -n "$branch" ] || { erro "usage: git wt new <branch>"; exit 2; }
  require_main new

  path="$WT_ROOT/$branch"
  [ -e "$path" ] && { erro "already exists: $path"; exit 1; }

  # Off main explicitly, never off HEAD: this must not inherit whatever the
  # main checkout happens to be sitting on if it ever drifted.
  mkdir -p "$(dirname "$path")"
  git -C "$MAIN" worktree add -b "$branch" "$path" main || exit 1

  # .claude/settings.local.json is gitignored, so `git worktree add` does not
  # bring it — and without it every agent Bash call in the new worktree stops
  # for a permission prompt. A workflow built for agent work that disarms the
  # agent on step one is not a workflow.
  #
  # A SYMLINK, not a copy: a copy drifts, and drift in an allowlist is a
  # permission you believed you had revoked.
  # `ln -sfn`, not `ln -sf`: without -n a second run drops the link INSIDE the
  # target directory instead of replacing it.
  if [ -f "$MAIN/.claude/settings.local.json" ]; then
    mkdir -p "$path/.claude"
    ln -sfn "$MAIN/.claude/settings.local.json" "$path/.claude/settings.local.json"
    info "linked .claude/settings.local.json from the main checkout"
  fi

  echo
  info "worktree ready — the machine is untouched, \$HOME still points at main"
  echo
  echo "    cd $path"
  echo
  info "when it is done, from the main checkout:"
  echo
  echo "    git wt promote $branch"
  echo
}

# ── list ────────────────────────────────────────────────────────────────────
handle_worktree_list() {
  local rec="$1" path branch tags=""
  path="$(porcelain_field "$rec" worktree)"
  branch="$(porcelain_field "$rec" branch)"; branch="${branch#refs/heads/}"
  porcelain_has "$rec" detached && branch="(detached)"

  if [ "$path" = "$MAIN" ]; then
    printf '  %-42s %-24s %s\n' "$path" "$branch" "← main checkout, THE LIVE CONFIG"
    return 0
  fi
  is_dirty "$path" && tags="$tags dirty"
  printf '%s\n' "$rec" | grep -q '^locked' && tags="$tags locked"
  [ "$branch" != "(detached)" ] && is_merged "$branch" && tags="$tags merged"
  [ -n "$tags" ] || tags=" —"
  printf '  %-42s %-24s %s\n' "$path" "$branch" "${tags# }"
}

cmd_list() {
  printf '  %-42s %-24s %s\n' "WORKTREE" "BRANCH" "STATE"
  handle_worktree() { handle_worktree_list "$1"; }
  for_each_worktree
}

# ── clean ───────────────────────────────────────────────────────────────────
CLEAN_YES=0
_removable=0
_kept=0

handle_worktree_clean() {
  local rec="$1" path branch reason=""
  path="$(porcelain_field "$rec" worktree)"
  [ "$path" = "$MAIN" ] && return 0          # git refuses anyway; do not even look
  branch="$(porcelain_field "$rec" branch)"; branch="${branch#refs/heads/}"

  if printf '%s\n' "$rec" | grep -q '^locked'; then
    reason="locked — someone locked it on purpose"
  elif porcelain_has "$rec" detached; then
    reason="detached — no branch to judge as merged"
  elif ! is_merged "$branch"; then
    reason="'$branch' is not merged into main — work would be lost"
  elif is_dirty "$path"; then
    reason="uncommitted changes"
  fi

  if [ -n "$reason" ]; then
    _kept=$((_kept + 1))
    printf '  %skeep%s   %-44s %s\n' $'\033[2m' $'\033[0m' "$path" "$reason"
    return 0
  fi

  _removable=$((_removable + 1))
  if [ "$CLEAN_YES" -eq 0 ]; then
    printf '  would remove  %-44s (%s, merged)\n' "$path" "$branch"
    return 0
  fi

  # No --force anywhere in this path. Everything above already proved the tree
  # is clean and unlocked; if git disagrees, git is right and we stop.
  if git -C "$MAIN" worktree remove "$path"; then
    printf '  removed       %-44s (%s)\n' "$path" "$branch"
    # -d, never -D: git refuses to delete an unmerged branch, so git itself is
    # the guard rather than our own merged check.
    git -C "$MAIN" branch -d "$branch" >/dev/null 2>&1 \
      && printf '  deleted branch %s\n' "$branch"
    prune_empty_dirs "$path"
  else
    erro "could not remove $path — left alone"
  fi
  return 0
}

cmd_clean() {
  [ "${1:-}" = "--yes" ] && CLEAN_YES=1
  [ -n "${1:-}" ] && [ "${1:-}" != "--yes" ] && { erro "unknown argument: $1"; exit 2; }
  require_main clean

  handle_worktree() { handle_worktree_clean "$1"; }
  for_each_worktree

  # Safe unconditionally: prune only reaps admin entries whose directory is
  # already gone. It never removes a worktree that exists.
  git -C "$MAIN" worktree prune

  echo
  if [ "$_removable" -eq 0 ]; then
    info "nothing to remove ($_kept kept)"
  elif [ "$CLEAN_YES" -eq 0 ]; then
    info "$_removable removable, $_kept kept — nothing was touched"
    info "to remove them:  git wt clean --yes"
  else
    info "$_removable removed, $_kept kept"
  fi
}

# ── promote ─────────────────────────────────────────────────────────────────
cmd_promote() {
  local branch="${1:-}" path head
  [ -n "$branch" ] || { erro "usage: git wt promote <branch>"; exit 2; }
  require_main promote

  # This merges into the LIVE config. Refuse unless main is exactly where it
  # should be, because a fast-forward onto the wrong thing reconfigures the
  # machine and there is no undo that a new shell would not have already read.
  head="$(git -C "$MAIN" symbolic-ref --quiet --short HEAD || echo '(detached)')"
  [ "$head" = main ] || { erro "the main checkout is on '$head', not main"; exit 1; }
  if [ -n "$(git -C "$MAIN" status --porcelain)" ]; then
    erro "the main checkout has uncommitted changes"
    info "commit or stash them first — this merge changes the live config"
    exit 1
  fi

  path="$WT_ROOT/$branch"
  if is_dirty "$path"; then
    erro "$path has uncommitted changes — commit them first"
    exit 1
  fi

  # This order is the only one that cannot strand you: `git branch -d` refuses a
  # branch checked out in a worktree, and `git worktree remove` refuses a dirty
  # tree. Merging INTO main while <branch> is checked out elsewhere is allowed;
  # only checking <branch> out twice is not.
  git -C "$MAIN" merge --ff-only "$branch" || {
    erro "not a fast-forward — rebase the branch onto main first"
    info "    cd $path"
    info "    git rebase main"
    exit 1
  }
  git -C "$MAIN" worktree remove "$path" && info "removed $path"
  git -C "$MAIN" branch -d "$branch"
  prune_empty_dirs "$path"

  echo
  info "merged into main. The live config is now this branch's content."
  echo
  "$MAIN/verify.sh"
}

case "${1:-}" in
  new)     shift; cmd_new "$@" ;;
  list|ls) shift; cmd_list "$@" ;;
  clean)   shift; cmd_clean "$@" ;;
  promote) shift; cmd_promote "$@" ;;
  -h|--help|help|'') usage ;;
  *) erro "unknown command: $1"; echo; usage; exit 2 ;;
esac
