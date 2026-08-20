#!/usr/bin/env bash
# PROPERTY: commands report honest exit codes, and nothing blocks waiting for
# a human.
#
# WHY THIS MATTERS
#   Two distinct turn-wasters:
#   (a) A replacement tool that exits 0 on failure makes an agent believe a
#       step worked. It proceeds on a false premise — the worst failure mode,
#       because the error surfaces far from its cause.
#   (b) A command that opens a pager or an editor never returns. The agent
#       hangs until it times out. Measured during this repo's own development:
#       `starship config` opened vim and blocked for 120s.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "▸ honest exit codes, and nothing blocks"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf 'hello\n' > "$TMP/file.txt"

# (a) failure must be reported as failure
assert_fails "ls <missing> fails"       zsh_interactive "ls '$TMP/nope' 2>/dev/null"
assert_fails "cat <missing> fails"      zsh_interactive "cat '$TMP/nope' 2>/dev/null"
assert_rc "grep with no match is 1"   1 zsh_interactive "grep zzz '$TMP/file.txt'"
assert_rc "grep with a match is 0"    0 zsh_interactive "grep hello '$TMP/file.txt'"

# (b) nothing may block. `timeout` returns 124 when it has to kill the child;
# any 124 here means an agent would have hung.
for c in "cat '$TMP/file.txt'" "ls '$TMP'" "git -C '$TMP' status" ; do
  rc=0
  timeout 10 zsh -f -c "source '$ZSHRC' >/dev/null 2>&1; $c" >/dev/null 2>&1 || rc=$?
  if [ "$rc" = 124 ]; then bad "does not block: $c" "timed out — a pager or prompt is waiting for input"
  else ok "does not block: $c"; fi
done

# bat must never page. Paging is what turns `cat` into a trap for agents.
paging="$(zsh_interactive 'print -r -- ${aliases[cat]}')"
case "$paging" in
  *--paging=never*) ok "cat alias disables paging explicitly" ;;
  "")               ok "cat alias disables paging explicitly" ;;   # no alias at all is fine
  *)                bad "cat alias disables paging explicitly" "alias is: $paging" ;;
esac

summary
