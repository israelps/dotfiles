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
         starship/.config/starship.toml ghostty/.config/ghostty/config \
         claude/.claude/rules/context7.md docs/claude-code-tuning.md; do
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
         ssh/.ssh/known_hosts .rtk-eval/bin/rtk claude/.claude/settings.json; do
  if git check-ignore -q "$f" 2>/dev/null; then
    ok "$f is blocked"
  else
    bad "$f is blocked" "no .gitignore rule covers it"
  fi
done

# --- no tracked file may point at a .zshrc block BY NUMBER -----------------
# Numbering is positional, so inserting one block silently invalidates every
# reference below it — and nothing errors. Measured: a conda block added to
# `zsh/.zshrc` shifted the sections and left BOTH existing pointers wrong (the
# Brewfile aimed "block 8" at syntax-highlighting, by then the 9th; a comment
# aimed "block 5" at the prompt, by then the 6th). Neither was noticed until
# the block came out. Name the section instead — a name does not shift.
numeric="$(git grep -nE '\.zshrc block [0-9]|block [0-9]+ of .*\.zshrc' 2>/dev/null | tr '\n' ' ' || true)"
if [ -n "$numeric" ]; then
  bad "no tracked file points at a .zshrc block by number" "$numeric"
else
  ok "no tracked file points at a .zshrc block by number"
fi

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

# --- a counted claim in a doc is a claim nobody checks ---------------------
# Both of these were already wrong before anyone noticed: README said "9 suites"
# while tests/ held 10, and named `rules/{shell,tests}.md` while .claude/rules/
# held four files. This repo's whole argument is that a number needs something
# behind it; a number in its own README is not exempt.
# The claim is the NUMBER, so that is what is matched — not the prose around
# it. Pinning the whole phrase would make this fail when the sentence is
# reworded, which is asserting the punctuation instead of the fact.
n_suites="$(find "$DOTFILES_DIR/tests" -name '*.test.sh' 2>/dev/null | wc -l | tr -d ' ')"
if grep -q "+ $n_suites suites" README.md 2>/dev/null; then
  ok "README's suite count matches tests/ ($n_suites)"
else
  bad "README's suite count matches tests/" \
      "tests/ holds $n_suites; README says: $(grep -o '+ [0-9]* suites' README.md 2>/dev/null || echo '(no count found)')"
fi

# Every rule file has to be named in README's tree. Asserting the brace
# expansion literally would test the punctuation; this tests the claim.
missing_rules=""
for r in "$DOTFILES_DIR"/.claude/rules/*.md; do
  [ -e "$r" ] || continue
  base="$(basename "$r" .md)"
  grep -q "$base" README.md 2>/dev/null || missing_rules="$missing_rules $base"
done
if [ -n "$missing_rules" ]; then
  bad "README names every rule in .claude/rules/" "missing:$missing_rules"
else
  ok "README names every rule in .claude/rules/"
fi

summary
