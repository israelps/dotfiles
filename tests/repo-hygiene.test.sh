#!/usr/bin/env bash
# PROPERTY: the repo publishes what it means to, and nothing it does not.
#
# WHY THIS MATTERS
#   A .gitignore rule that is too broad hides a file you meant to ship, and it
#   does so in silence. This suite exists because a blanket `.ssh/` rule —
#   written to block private keys — also swallowed this repo's own generic ssh
#   fragment. The commit would have shipped without it and nobody would know.
#   The opposite failure is worse: a rule too narrow ships a key.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "▸ repository hygiene"

cd "$DOTFILES_DIR" || { bad "cannot enter repo"; summary; exit 1; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  git not available"; exit 0; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "  SKIP  not a git repo yet"; exit 0; }

# --- must SHIP -------------------------------------------------------------
for f in ssh/.ssh/config.d/10-multiplex.conf zsh/.zshrc verify.sh CLAUDE.md \
         starship/.config/starship.toml ghostty/.config/ghostty/config; do
  if git check-ignore -q "$f" 2>/dev/null; then
    bad "$f is publishable" "a .gitignore rule is hiding it"
  else
    ok "$f is publishable"
  fi
done

# --- must NEVER ship -------------------------------------------------------
# Probe with paths that do not exist: check-ignore answers on the rule, not the
# file, so this needs no fixture and leaves nothing behind.
for f in ssh/.ssh/id_rsa ssh/.ssh/id_ed25519 .env .claude/settings.local.json \
         ssh/.ssh/known_hosts .rtk-eval/bin/rtk; do
  if git check-ignore -q "$f" 2>/dev/null; then
    ok "$f is blocked"
  else
    bad "$f is blocked" "no .gitignore rule covers it"
  fi
done

# --- nothing tracked may carry a personal absolute path --------------------
# The pattern is BUILT at runtime on purpose. Written literally, this file would
# contain the very string it forbids and the check would fail on itself — a
# prohibition regex matching the comment that documents the prohibition. It did,
# on the first run.
home_pat="/$(printf 'Users')/"
# `|| true`: grep exits 1 when it finds nothing, and the substitution would
# propagate that into the ERR trap — reporting a false suite error on success.
hits="$(git ls-files -z 2>/dev/null | xargs -0 grep -lI "$home_pat" 2>/dev/null | tr '\n' ' ' || true)"
if [ -n "$hits" ]; then
  bad "no tracked file hardcodes a personal home path" "$hits"
else
  ok "no tracked file hardcodes a personal home path"
fi

summary
