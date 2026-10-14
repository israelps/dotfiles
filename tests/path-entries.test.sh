#!/usr/bin/env bash
# PROPERTY: every directory .zshrc prepends to $PATH exists, or is guarded by a
# test of that same directory.
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
#   UNGUARDED lines (column 0, `export PATH="…"`) must name a directory that
#   exists. A GUARDED one-liner (`[ -d "X" ] && export PATH="X:$PATH"`) is
#   allowed to name one that does not, because it tests before it uses — that
#   is what makes the file portable to a machine without Rancher Desktop, whose
#   `~/.rd/bin` failed this suite on any such machine until 2026-10-14. What a
#   guarded line must do instead is test the SAME directory it adds: a guard on
#   X that prepends Y is a dead entry wearing a guard.
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

# Guarded one-liners: compare the guard's directory with the prepended one, as
# text. Existence is deliberately NOT checked — absence is what the guard is for.
while IFS= read -r line; do
  guard="$(printf '%s\n' "$line" | sed -E 's/^\[ -d "([^"]+)" \].*/\1/')"
  # shellcheck disable=SC2016  # `$PATH` is the literal text being matched
  added="$(printf '%s\n' "$line" | sed -E 's/.*export PATH="([^":]+):\$PATH".*/\1/')"
  checked=$((checked + 1))
  if [ "$guard" = "$added" ]; then
    ok "guarded PATH entry tests what it adds: $added"
  else
    bad "guarded PATH entry tests what it adds: $added" \
        "the guard tests $guard — when $added is missing it is still prepended"
  fi
done < <(grep -E '^\[ -d "[^"]+" \] && export PATH="' "$ZSHRC")

# Non-vacuity: a grep that stopped matching would leave this suite green having
# checked nothing at all. Both forms count — the threshold did not move when the
# lines changed form.
if [ "$checked" -ge 2 ]; then
  ok "found PATH lines to check ($checked)"
else
  bad "found PATH lines to check" \
      "only $checked matched — .zshrc changed shape or the grep broke; this check was vacuous"
fi

summary
