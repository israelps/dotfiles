#!/usr/bin/env bash
# Which checkout is this, and is it the one wired into $HOME?
#
# WHY THIS EXISTS
#   The working tree IS the live config: ~/.zshrc and friends are stow symlinks
#   pointing into it. Branch work therefore happens in linked worktrees, where
#   nothing under $HOME points — see docs/worktree-workflow.md. That splits
#   every assertion in tests/ into two kinds:
#
#     * a FILE property   — "this config parses", "no alias shadows grep".
#                           True or false in any checkout. Always runs.
#     * a LIVE property   — "$HOME/.zshrc is this file", "ssh -G resolves the
#                           Include". Only meaningful where stow ran.
#
#   A live assertion in a linked worktree is not a failure and is not a pass.
#   It is a question that does not apply, and it has to say so out loud.
#
# SOURCED BY tests/lib.sh AND verify.sh, so it sets no shell option, installs
# no trap, and creates nothing. Both callers run under their own `set`, and a
# file that changes that from underneath them is a file nobody can source.

# Identity is device:inode, never a resolved path. macOS ships neither
# realpath(1) nor `readlink -f`, and the usual `stat -f … || stat -c …` chain
# is a trap: on GNU, -f means FILESYSTEM, takes no format, and prints several
# lines to STDOUT before exiting 1 — so the fallback's answer arrives glued to
# that output, and only stderr was ever redirected. Probe the dialect ONCE,
# against a path that exists everywhere, and the whole class is gone.
if stat -L -f '%d:%i' / >/dev/null 2>&1; then
  _STAT_ID_ARGS='-L -f %d:%i'      # BSD / macOS
  _STAT_MODE_ARGS='-L -f %Lp'
else
  _STAT_ID_ARGS='-L -c %d:%i'      # GNU
  _STAT_MODE_ARGS='-L -c %a'
fi

# _inode <path> -> "<dev>:<ino>", or a path-unique sentinel when it cannot be
# stat'ed. NEVER returns non-zero: every call site is `x="$(_inode …)"`, and a
# failing command substitution in an assignment DOES trip lib.sh's ERR trap
# (measured: `x=$(false)` sets it; `( false )` does not).
#
# The sentinel embeds the path so two MISSING files never compare equal — a
# dangling ~/.zshrc and a deleted repo file must not look like a match.
_inode() {
  # shellcheck disable=SC2086  # deliberate word splitting: dialect flags
  stat $_STAT_ID_ARGS "$1" 2>/dev/null || printf 'none:%s\n' "$1"
}

# _mode <path> -> permission bits as octal digits ("700"), or "none". Same
# one-time dialect probe, same reason: the `-f … || -c …` chain is a trap.
_mode() {
  # shellcheck disable=SC2086
  stat $_STAT_MODE_ARGS "$1" 2>/dev/null || printf 'none\n'
}

# checkout_state -> prints exactly one of: stowed | worktree | absent
#
#   stowed    $HOME/.zshrc IS this checkout's file. Live checks apply.
#   worktree  this is a linked worktree whose MAIN worktree is the stowed one.
#             Live checks are skipped — they would describe another checkout.
#   absent    anything else. Live checks RUN, so they fail and say so.
#
# ALWAYS returns 0, for the ERR-trap reason above. Reads $HOME and
# $DOTFILES_DIR at call time and caches nothing, so tests/worktree.test.sh can
# drive every row of the table from a hermetic fixture.
#
# The probe is $HOME/.zshrc <-> <checkout>/zsh/.zshrc, and the choice matters:
# both ends of that pair are named by ZSH, not by this repo. Renaming the ssh
# fragment or dropping the ghostty package would silently flip a probe keyed on
# those; .zshrc is the one file whose absence means "nothing is installed".
checkout_state() {
  local live repo main main_id

  live="$(_inode "$HOME/.zshrc")"
  repo="$(_inode "${DOTFILES_DIR:-.}/zsh/.zshrc")"

  [ "$live" = "$repo" ] && { printf 'stowed\n'; return 0; }

  # Not ours. The ONLY honest reason to skip a live check is that the machine
  # is configured by the main worktree of THIS repository and we are a branch
  # of it. That needs positive proof — without it, a linked worktree of some
  # unrelated clone would earn a permanent free pass, which is exactly the
  # vacuous green this repo exists to prevent.
  #
  # `git worktree list` documents the main worktree as the first record. sed,
  # not awk: the porcelain format does not quote, so a path containing a space
  # survives `sed -n 's/^worktree //p'` and dies in `awk '{print $2}'`.
  main="$(git -C "${DOTFILES_DIR:-.}" worktree list --porcelain 2>/dev/null \
          | sed -n '1s/^worktree //p')"
  [ -n "$main" ] || { printf 'absent\n'; return 0; }

  main_id="$(_inode "$main/zsh/.zshrc")"

  # We ARE the main worktree — compared by inode, not by path text, because
  # DOTFILES_DIR is built with `pwd` and not `pwd -P`, so a symlinked path
  # would defeat a string compare — and yet $HOME does not point here. Stow
  # never ran, or it ran from somewhere else. That is `absent`: fail, never
  # skip.
  [ "$main_id" = "$repo" ] && { printf 'absent\n'; return 0; }

  [ "$live" = "$main_id" ] && { printf 'worktree\n'; return 0; }
  printf 'absent\n'
  return 0
}

# main_worktree_path -> absolute path of this repository's main worktree, empty
# if this is not a git checkout. Used by the tests to name what they skipped.
main_worktree_path() {
  git -C "${DOTFILES_DIR:-.}" worktree list --porcelain 2>/dev/null \
    | sed -n '1s/^worktree //p'
}
