#!/usr/bin/env bash
# PROPERTY: every rule declares what it is and what backs it, in a closed
# vocabulary, and stays inside the context ceiling.
#
# WHY THIS MATTERS
#   A rule file is read by an agent, in the middle of a task, at the moment the
#   glob fires. Two failures make it worse than absent. Without `description:`
#   nothing can say what it covers before loading it. Without `proved-by:` a
#   norm nobody measured looks exactly like one that a suite enforces — and this
#   repo's whole claim is that its choices were measured, so an unbacked norm
#   sitting among backed ones spends credibility it did not earn.
#   The norms themselves live in `.claude/rules/policy-layer.md`; this suite is
#   the mechanical half — the half a machine can actually check.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "▸ rule hygiene"

cd "$DOTFILES_DIR" || { bad "cannot enter repo"; summary; exit 1; }

CEILING=200
checked=0

for f in .claude/rules/*.md claude/.claude/rules/*.md; do
  [ -e "$f" ] || continue
  checked=$((checked + 1))

  # Frontmatter must open on line 1: a `---` anywhere later is a horizontal
  # rule in the prose, not a header, and the loader would read neither.
  if [ "$(head -1 "$f")" != "---" ]; then
    bad "$f opens with frontmatter" "line 1 is not ---"
    continue
  fi
  # Line number of the CLOSING ---, so the greps below cannot match prose.
  fm_end="$(awk 'NR>1 && $0=="---" {print NR; exit}' "$f")"
  if [ -z "$fm_end" ]; then
    bad "$f closes its frontmatter" "no second --- found"
    continue
  fi
  fm="$(head -n "$fm_end" "$f")"

  case "$fm" in
    *"description:"*) ok "$f declares description" ;;
    *) bad "$f declares description" "no description: in the frontmatter" ;;
  esac

  proved="$(printf '%s\n' "$fm" | sed -n 's/^proved-by:[[:space:]]*//p' | head -1)"
  if [ -z "$proved" ]; then
    bad "$f declares proved-by" "no proved-by: in the frontmatter — see .claude/rules/policy-layer.md"
    continue
  fi

  # Closed vocabulary. A path term must also RESOLVE: a rule pointing at a test
  # that no longer exists is the failure this check is for, and it reads exactly
  # like a rule that is enforced.
  case "$proved" in
    none|not-applicable)
      ok "$f proved-by is closed vocabulary ($proved)" ;;
    tests/*)
      if [ -e "$proved" ]; then ok "$f proved-by resolves ($proved)"
      else bad "$f proved-by resolves" "$proved does not exist"; fi ;;
    README.md\ §\ *|docs/*.md)
      target="${proved%% §*}"
      if [ -e "$target" ]; then ok "$f proved-by resolves ($proved)"
      else bad "$f proved-by resolves" "$target does not exist"; fi ;;
    *)
      bad "$f proved-by is closed vocabulary" \
          "'$proved' is not one of: tests/<file> | README.md § <section> | docs/<file>.md | none | not-applicable" ;;
  esac

  n="$(wc -l < "$f" | tr -d ' ')"
  if [ "$n" -le "$CEILING" ]; then ok "$f is within $CEILING lines ($n)"
  else bad "$f is within $CEILING lines" "$n lines — a long rule eats context and lowers adherence"; fi
done

# Non-vacuity. lib.sh refuses a suite with zero assertions, but a glob that
# silently matched one file would still report green.
if [ "$checked" -ge 3 ]; then
  ok "found the rule files ($checked)"
else
  bad "found the rule files" "only $checked matched — the glob no longer fits .claude/rules/"
fi

summary
