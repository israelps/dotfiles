#!/usr/bin/env bash
# Shared by every Claude Code hook in this directory.
#
# WHY THE SCRIPTS ARE VERSIONED AND THE WIRING IS NOT
#   .claude/settings.json is gitignored on purpose — Claude Code rewrites it at
#   runtime. If the policy lived inside that JSON it would be invisible to
#   verify.sh, absent from a fresh clone, and unversioned: a rule with no test,
#   which is the one thing this repo does not ship. So the policy lives here,
#   in files the suite can drive, and install.sh writes only the pointer. Same
#   split as .githooks/ plus core.hooksPath.
#
# FAIL OPEN, AND LOUDLY
#   A guard that bricks the session is a guard the owner turns off, and then
#   there is no guard at all. Every failure path here lets the tool call
#   proceed and says so on stderr. tests/claude-hooks.test.sh is what catches a
#   guard that stopped working — not the session dying.

# The hook's own location is the only reliable anchor: $PWD is wherever the
# agent happens to be, and $CLAUDE_PROJECT_DIR is not guaranteed to be set.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$HOOK_DIR/../.." && pwd)"
export DOTFILES_DIR

# checkout_state() lives in tests/, because that is where it is exercised. It
# is a pure-function file by design — no `set`, no traps, no side effects —
# precisely so callers like this one can source it safely.
# shellcheck source=tests/checkout-state.sh
. "$DOTFILES_DIR/tests/checkout-state.sh"

HOOK_INPUT="$(cat)"

# hook_field <jq-path> -> the value, or empty. Never fails the caller.
hook_field() {
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$HOOK_INPUT" | jq -r "$1 // empty" 2>/dev/null
}

# allow — let the call through, silently. The default for everything.
allow() { exit 0; }

# fail_open <why> — something in this guard broke. Say so where the owner can
# see it, then get out of the way.
fail_open() {
  printf 'hook %s could not decide (%s) — allowing the call\n' "${0##*/}" "$1" >&2
  exit 0
}

# deny <reason> — refuse the tool call and tell the model why, in the words it
# needs to act on. exit 0 with JSON rather than exit 2: the JSON form carries a
# reason the model reads as guidance, where exit 2 carries only stderr.
deny() {
  command -v jq >/dev/null 2>&1 || fail_open "jq is missing, cannot emit a decision"
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# block <reason> — for a PostToolUse hook, where the call has already run. The
# shape is different from deny()'s on purpose: PreToolUse decides a permission,
# PostToolUse can only interrupt what follows and hand back a reason. Both are
# the documented forms for their event; neither works in the other's place.
block() {
  command -v jq >/dev/null 2>&1 || fail_open "jq is missing, cannot emit a decision"
  jq -n --arg r "$1" '{decision: "block", reason: $r}'
  exit 0
}

# stow_packages -> the package names, read from install.sh, which is the single
# place they are declared. A second copy here would be a second thing to keep
# honest; policy-layer.md asks for the disagreement to be impossible.
stow_packages() {
  sed -n 's/^PACKAGES=(\(.*\))$/\1/p' "$DOTFILES_DIR/install.sh" | tr ' ' '\n' | sed '/^$/d'
}

# package_of <path> -> the stow package the path falls inside, or empty.
#
# Shared, not copied. guard-live-edit.sh gets a .tool_input.file_path and
# guard-live-write.sh digs targets out of a .tool_input.command; if each decided
# "is this live?" on its own the two would drift, and one of them would be
# wrong with nothing to say so. policy-layer.md asks for that disagreement to be
# impossible, so there is one answer and both call it.
#
# Resolves a leading ~/ and follows a symlink, because ~/.zshrc IS the live
# file: it points into this checkout, so writing through it is the same
# overwrite as writing zsh/.zshrc directly.
package_of() {
  local path="$1" abs rel pkg p link
  [ -n "$path" ] || return 0

  case "$path" in
    "~/"*) abs="$HOME/${path#\~/}" ;;
    /*)    abs="$path" ;;
    *)     abs="$DOTFILES_DIR/$path" ;;
  esac

  if [ -L "$abs" ]; then
    link="$(readlink "$abs")"
    case "$link" in
      /*) abs="$link" ;;
      *)  abs="$(cd "$(dirname "$abs")" 2>/dev/null && cd "$(dirname "$link")" 2>/dev/null && pwd)/$(basename "$link")" ;;
    esac
  fi

  case "$abs" in
    "$DOTFILES_DIR"/*) rel="${abs#"$DOTFILES_DIR"/}" ;;
    *) return 0 ;;                    # not this repo at all
  esac

  pkg="${rel%%/*}"
  [ "$pkg" != "$rel" ] || return 0    # a file at the repo root is not a package

  while IFS= read -r p; do
    [ "$p" = "$pkg" ] && { printf '%s\n' "$pkg"; return 0; }
  done <<EOF
$(stow_packages)
EOF
  return 0
}

# dirty_packages -> one porcelain line per changed file inside a stow package,
# sorted. This is the whole live surface in one string: comparable, cheap, and
# blind to HOW the change arrived, which is the point. The PreToolUse guards
# read commands and can be fooled by an interpreter; git cannot.
dirty_packages() {
  local pkgs
  pkgs="$(stow_packages | tr '\n' ' ')"
  # shellcheck disable=SC2086
  git -C "$DOTFILES_DIR" status --porcelain=v1 -- $pkgs 2>/dev/null | LC_ALL=C sort
}

# drift_baseline <session-id> -> path to this session's snapshot of the live
# surface, or EMPTY when there is no session id. Per session, in TMPDIR: the
# question is always "did THIS session move it", never "is it dirty", because
# the owner's own uncommitted work must never read as the agent's doing.
#
# It returns empty rather than falling back to a shared name, and that is not
# fussiness. guard-stop.sh can safely default its marker to "unknown" — sharing
# a "already warned once" flag costs nothing. Sharing a BASELINE is the
# cross-session contamination this whole mechanism exists to prevent: session A
# would inherit B's floor and either accuse B's work or excuse its own. Found
# on 2026-08-25 by an unexplained dotfiles-drift-unknown appearing in TMPDIR
# from a real hook call whose payload carried no session_id.
drift_baseline() {
  [ -n "${1:-}" ] || return 0
  printf '%s/dotfiles-drift-%s\n' "${TMPDIR:-/tmp}" "$1"
}
