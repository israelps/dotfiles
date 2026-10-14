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

# --- an unbraced expansion must not touch a multibyte character ------------
# Measured while writing .githooks/post-checkout: an expansion written directly
# against a box-drawing character makes the shell scan the longest valid
# identifier after the dollar and eat that character's leading 0xe2 byte into
# the variable NAME. The siren's frame rendered with a replacement character.
# Braced, the line starts e2 94 80; unbraced, 94 80.
#
# The class lists the multibyte characters this repo actually uses, and that is
# a STATED LIMIT, not an oversight: BSD grep in a UTF-8 locale cannot match a
# raw byte range, so `[\200-\377]` silently matches nothing. Verified both ways
# against a fixture — the literal class finds the broken form and leaves the
# braced one alone; the byte range found neither.
mb='\$[A-Za-z_][A-Za-z0-9_]*[─—▸·§→←]'
unbraced="$(git ls-files -z 2>/dev/null | xargs -0 grep -ln "$mb" 2>/dev/null | tr '\n' ' ' || true)"
if [ -n "$unbraced" ]; then
  bad "no tracked file expands a variable straight into a multibyte character" \
      "$unbraced — use \${VAR} there"
else
  ok "no tracked file expands a variable straight into a multibyte character"
fi

# --- undated numbers: a ratchet, not a wall --------------------------------
# A number that passed its controls still rots, because what it measured keeps
# changing. Measured on 2026-08-25: zsh/.zshrc claimed a second `compinit`
# "cost ~190 ms per shell". Re-taken with measure/compare.sh it was +15.9 ms of
# prompt lag and -50.6 ms of first-command lag — a trade, not a cost. The old
# figure was not wrong when written; ZSH_DISABLE_COMPFIX landed afterwards and
# took ~29 ms of compaudit out of exactly that path. Nothing said so, because
# the number carried no date.
#
# This is a CEILING THAT MAY FALL AND MAY NOT RISE. Failing on the whole
# backlog would force someone to date numbers they cannot re-take today, which
# buys a green suite with invented provenance — the very trade signals.md
# forbids. Lower it when you re-measure something; never raise it.
UNDATED_CEILING=5
undated=0; withnum=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -qE '[0-9]+(\.[0-9]+)? ?ms\b' "$f" 2>/dev/null || continue
  withnum=$((withnum + 1))
  grep -qE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$f" 2>/dev/null || undated=$((undated + 1))
done < <(git ls-files 2>/dev/null || true)

if [ "$withnum" -eq 0 ]; then
  bad "the millisecond-claim scan found files to look at" \
      "it matched nothing — the scan rotted, which reads exactly like a clean repo"
elif [ "$undated" -le "$UNDATED_CEILING" ]; then
  ok "undated numeric claims: $undated of $withnum files, ceiling $UNDATED_CEILING"
else
  bad "undated numeric claims stay at or below the ceiling" \
      "$undated of $withnum files carry a number and no date, ceiling is $UNDATED_CEILING — date it, or re-take it with measure/compare.sh"
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

# Every suite has a row in README's property table. The count above held while
# the table listed 10 of 14 — a count and a list are different claims, and
# only one of them was checked. Found 2026-10-14, before the repo went public.
missing_rows=""
for t in "$DOTFILES_DIR"/tests/*.test.sh; do
  [ -e "$t" ] || continue
  name="$(basename "$t" .test.sh)"
  grep -q "^| \`$name\` |" README.md 2>/dev/null || missing_rows="$missing_rows $name"
done
if [ -n "$missing_rows" ]; then
  bad "README's property table has a row for every suite" "missing:$missing_rows"
else
  ok "README's property table has a row for every suite"
fi

# A `README § <Heading>` pointer in any tracked file names a heading that
# exists. Brewfile pointed at three that never did (§ Measurements, § myths,
# § The problem) — found 2026-10-14. A pointer is matched by PREFIX, because it
# sits inside prose: "README § Prompt choice simply becomes…" is fine. A
# placeholder (`§ <section>`, as policy-layer.md writes it) is not a pointer.
headings="$(sed -n -E 's/^#+ //p' README.md | tr -d '*')"
refs="$(git grep -h -o -E 'README(\.md)? § [^|]*' 2>/dev/null || true)"
nrefs=0; dangling=""
while IFS= read -r m; do
  [ -n "$m" ] || continue
  ref="${m#*§ }"
  case "$ref" in '<'*) continue ;; esac
  nrefs=$((nrefs + 1))
  found=0
  while IFS= read -r h; do
    case "$ref" in "$h"*) found=1; break ;; esac
  done <<< "$headings"
  [ "$found" -eq 1 ] || dangling="$dangling | ${ref%%[).,;]*}"
done <<< "$refs"
if [ "$nrefs" -eq 0 ]; then
  bad "every § pointer into README names a real heading" "found none — the grep broke; the Prompt choice section is cited in several files"
elif [ -n "$dangling" ]; then
  bad "every § pointer into README names a real heading" "no such heading:$dangling"
else
  ok "every § pointer into README names a real heading ($nrefs checked)"
fi

summary
