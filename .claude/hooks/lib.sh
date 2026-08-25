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

# stow_packages -> the package names, read from install.sh, which is the single
# place they are declared. A second copy here would be a second thing to keep
# honest; policy-layer.md asks for the disagreement to be impossible.
stow_packages() {
  sed -n 's/^PACKAGES=(\(.*\))$/\1/p' "$DOTFILES_DIR/install.sh" | tr ' ' '\n' | sed '/^$/d'
}
