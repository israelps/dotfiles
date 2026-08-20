#!/usr/bin/env bash
# PROPERTY: no alias shadows a POSIX command outside an interactive shell.
#
# WHY THIS MATTERS
#   AI CLI agents capture your shell state and replay it in a shell whose $-
#   has no `i`. Measured on this machine: Claude Code's Bash tool runs with
#   $- = 569JNRXghkl, yet an unguarded `alias cat=bat` still applied — and
#   `cat -v file` failed, because bat has no -v. That is one wasted turn,
#   every time.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "▸ no POSIX shadowing in non-interactive shells"

# These must resolve to a real command, never to an alias/function, when the
# shell is not interactive.
for cmd in ls cat grep curl find tree sed awk head tail sort; do
  kind="$(zsh_noninteractive "whence -w $cmd 2>/dev/null | cut -d: -f2 | tr -d ' '")"
  case "$kind" in
    alias) bad "$cmd is a real command (not an alias)" "resolved as: alias" ;;
    "")    ok  "$cmd is a real command (not an alias)" ;;   # absent = nothing shadowing
    *)     ok  "$cmd is a real command (not an alias)" ;;
  esac
done

# The interactive convenience must still be there — the point is separation,
# not abstinence. If this fails, the guard is too aggressive.
kind_i="$(zsh_interactive 'whence -w ls | cut -d: -f2 | tr -d " "')"
assert_eq "ls IS an alias in an interactive shell (convenience preserved)" "alias" "$kind_i"

summary
