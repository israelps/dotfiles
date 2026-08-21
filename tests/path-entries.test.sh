#!/usr/bin/env bash
# PROPERTY: every directory .zshrc prepends to $PATH exists.
#
# WHY THIS MATTERS
#   A dead $PATH entry is silent. Nothing errors, nothing warns — the shell just
#   stats a directory that is not there on every single command lookup, forever.
#   It is also the exact residue an uninstalled tool leaves behind: installers
#   append their line to `.zshrc` and uninstallers do not take it back out.
#   Found three at once on 2026-08-21 — `openjdk`, whose formula was gone, and
#   two written into this repo by Antigravity's installer, still prepending
#   after the app was removed. `~/.zshrc` is a symlink into this repo, so a
#   third-party installer editing it edits TRACKED source.
#
#   Only UNGUARDED lines are checked, and the grep enforces that by anchoring on
#   column 0. The conda block prepends from inside `if [ -x .../conda ]` — it is
#   allowed to name a directory that does not exist, because it tests first.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "▸ every PATH entry resolves"

checked=0
while IFS= read -r line; do
  seg="${line#export PATH=\"}"; seg="${seg%\"*}"
  seg="${seg%:\$PATH}"; seg="${seg#\$PATH:}"
  # Strip a trailing comment, then expand only what this file may legitimately use.
  dir="${seg%%\"*}"
  dir="${dir/\$HOME/$HOME}"
  checked=$((checked + 1))
  case "$dir" in
    *\$*) bad "PATH entry resolves: $seg" "expands a variable this test cannot resolve — is it guarded?" ;;
    *) if [ -d "$dir" ]; then ok "PATH entry resolves: $seg"
       else bad "PATH entry resolves: $seg" \
                "$dir does not exist — every command lookup stats it, and nothing ever says so"; fi ;;
  esac
done < <(grep -E '^export PATH="' "$ZSHRC")

# Non-vacuity: a grep that stopped matching would leave this suite green having
# checked nothing at all.
if [ "$checked" -ge 2 ]; then
  ok "found unguarded PATH lines to check ($checked)"
else
  bad "found unguarded PATH lines to check" \
      "only $checked matched — .zshrc changed shape or the grep broke; this check was vacuous"
fi

summary
