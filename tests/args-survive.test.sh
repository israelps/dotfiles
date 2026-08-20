#!/usr/bin/env bash
# PROPERTY: every convenience alias still works when given an argument.
#
# WHY THIS MATTERS
#   `eza --icons` takes an OPTIONAL value, so it swallows the next word:
#   `ls somedir/` died with "invalid value 'somedir/' for '--icons [<WHEN>]'".
#   This was broken on this machine for months. It costs a turn for an agent
#   and a double-take for a human. The fix is `--icons=auto`, with the `=`.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "▸ aliases survive being given arguments"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/sub"; printf 'hello\nRPIA line\n' > "$TMP/file.txt"

# Each of these is a shape an agent types constantly.
assert_rc "ls <dir>"            0 zsh_interactive "ls '$TMP'"
assert_rc "ls -la <dir>"        0 zsh_interactive "ls -la '$TMP'"
assert_rc "tree <dir>"          0 zsh_interactive "tree '$TMP'"
assert_rc "cat <file>"          0 zsh_interactive "cat '$TMP/file.txt'"
assert_rc "ll <dir>"            0 zsh_interactive "ll '$TMP'"
assert_rc "egrep -i <pat> <f>"  0 zsh_interactive "egrep -i rpia '$TMP/file.txt'"
assert_rc "fgrep <pat> <f>"     0 zsh_interactive "fgrep hello '$TMP/file.txt'"
assert_rc "grep -n <pat> <f>"   0 zsh_interactive "grep -n hello '$TMP/file.txt'"

# Non-vacuity: prove the commands actually produced the content we expect,
# not just a zero exit code.
out="$(zsh_interactive "cat '$TMP/file.txt'" | tr -d '\r')"
case "$out" in *hello*) ok "cat actually printed the file" ;;
               *)       bad "cat actually printed the file" "got: ${out:-<empty>}" ;; esac

summary
