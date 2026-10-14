#!/usr/bin/env bash
# PROPERTY: every dependency this config actually uses is installed, and every
# path the shell sources unconditionally exists.
#
# WHY THIS MATTERS
#   The other suites all run against a machine that already has the tools, so
#   they answer "is the config correct?" and never "is the config usable?".
#   Those are different questions and only one of them fails on a fresh laptop.
#   Two concrete failure modes this catches:
#     - `.zshrc` sources zsh-autosuggestions with no `[ -f ]` guard. Without the
#       formula, EVERY interactive shell opens with an error on stderr. An agent
#       that captures shell output reads that error as part of your answer.
#     - `fd` sat in the Brewfile, uninstalled, and nothing noticed. `brew bundle
#       check` would have said so, but it needs the network and it reports a
#       merely-outdated formula as unsatisfied — a red suite for a non-problem.
#       This suite asks the only question that matters offline: is it THERE?
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "▸ declared dependencies are installed"

cd "$DOTFILES_DIR" || { bad "cannot enter repo"; summary; exit 1; }

if ! command -v brew >/dev/null 2>&1; then
  echo "  SKIP  Homebrew not available — nothing here is meaningful without it"
  exit 0
fi
PREFIX="$(brew --prefix)"

# --- every Brewfile entry is present --------------------------------------
# The probe table is deliberately explicit: a formula name is NOT a binary name
# (ripgrep ships `rg`), and two entries ship no binary at all. The `*)` branch
# is the point — add a formula to the Brewfile without teaching this suite how
# to see it and the suite FAILS. That is what keeps the table from going stale
# in silence, which is the only way a check like this ever rots.
checked=0
while read -r kind name; do
  [ -n "${name:-}" ] || continue
  checked=$((checked + 1))
  case "$name" in
    ghostty)                 probe="app:/Applications/Ghostty.app" ;;
    zsh-autosuggestions)     probe="file:$PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ;;
    zsh-syntax-highlighting) probe="file:$PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ;;
    # A cask font installs into the user's Fonts folder, not the brew prefix.
    font-jetbrains-mono-nerd-font) probe="file:$HOME/Library/Fonts/JetBrainsMonoNerdFont-Regular.ttf" ;;
    ripgrep)                 probe="bin:rg" ;;
    coreutils)               probe="bin:timeout" ;;
    starship|stow|eza|bat|fd|fzf|zoxide|xh|shellcheck|gitleaks|tmux)
                             probe="bin:$name" ;;
    *)
      bad "$name has a probe in this suite" \
          "Brewfile declares '$kind \"$name\"' but tests/deps-installed.test.sh does not know how to detect it — add a case above"
      continue ;;
  esac

  target="${probe#*:}"
  case "$probe" in
    bin:*)  if command -v "$target" >/dev/null 2>&1
            then ok "$name is installed"
            else bad "$name is installed" "'$target' is not on \$PATH — run: brew bundle"; fi ;;
    file:*) if [ -f "$target" ]
            then ok "$name is installed"
            else bad "$name is installed" "missing $target — run: brew bundle"; fi ;;
    app:*)  if [ -d "$target" ]
            then ok "$name is installed"
            else bad "$name is installed" "missing $target — run: brew bundle"; fi ;;
  esac
done < <(sed -n -E 's/^(brew|cask) "([^"]+)".*/\1 \2/p' Brewfile)

# Non-vacuity guard. lib.sh already refuses a suite with zero assertions, but a
# sed that silently matched two lines would still report green. The Brewfile has
# never held fewer than a dozen entries; a count below that means the parse
# broke, not that the dependencies shrank.
if [ "$checked" -ge 12 ]; then
  ok "parsed the Brewfile ($checked entries)"
else
  bad "parsed the Brewfile" "only $checked entries matched — the sed pattern no longer fits Brewfile"
fi

# --- brew's own view of the same file --------------------------------------
# The table above proves PRESENCE, offline and by our own reckoning. This proves
# presence AND freshness, using brew's answer instead of ours. Both stay, because
# they fail on different things: the table is the one that catches a formula
# nobody taught this suite about, and it is the one that still runs when brew
# cannot reach its API.
#
# HOMEBREW_NO_AUTO_UPDATE=1 keeps a full repository refresh off the hot path of
# every ./verify.sh. It does NOT weaken the check — an outdated formula is still
# reported outdated; that is how `fzf` at 0.74.2 against a 0.74.3 stable was
# caught. Bounded, so a stalled API cannot hang the suite.
if ! command -v timeout >/dev/null 2>&1; then
  bad "brew bundle check passes" "cannot run it bounded — timeout(1) is missing, and macOS ships none"
else
  bundle_rc=0
  HOMEBREW_NO_AUTO_UPDATE=1 timeout 120 brew bundle check --file=Brewfile >/dev/null 2>&1 || bundle_rc=$?
  case "$bundle_rc" in
    0)   ok "brew bundle check passes" ;;
    124) bad "brew bundle check passes" "timed out after 120s — brew could not reach its API" ;;
    # `|| true`: brew exits non-zero here BY DEFINITION, and under pipefail
    # that made the assignment fail and trip lib.sh's ERR trap — every genuine
    # unmet dependency was reported a second time as "an unexpected shell error".
    *)   unmet="$(HOMEBREW_NO_AUTO_UPDATE=1 timeout 120 brew bundle check --verbose --file=Brewfile 2>&1 \
                  | sed -n -E 's/^.*(Formula|Cask) ([^ ]+) needs.*/\2/p' | tr '\n' ' ' || true)"
         bad "brew bundle check passes" "unmet: ${unmet:-rc=$bundle_rc} — run: brew bundle install" ;;
  esac
fi

# --- every unguarded `source` in .zshrc resolves --------------------------
# Only UNguarded lines are checked, and the grep enforces that by anchoring on
# `source` at column 0: `[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh` is allowed to
# point at nothing, because it tests before it sources. An unguarded one is not.
zsh_home="$(sed -n -E 's/^export ZSH="([^"]+)".*/\1/p' zsh/.zshrc)"
zsh_home="${zsh_home/\$HOME/$HOME}"
sourced=0
while read -r raw; do
  path="${raw#source \"}"; path="${path%\"}"
  path="${path/\$(brew --prefix)/$PREFIX}"
  path="${path/\$ZSH/$zsh_home}"
  path="${path/\$HOME/$HOME}"
  sourced=$((sourced + 1))
  if [ -f "$path" ]; then
    ok "unguarded source resolves: ${raw#source }"
  else
    bad "unguarded source resolves: ${raw#source }" \
        "missing $path — every interactive shell will print an error at startup"
  fi
done < <(grep -E '^source "' zsh/.zshrc)

if [ "$sourced" -gt 0 ]; then
  ok "found unguarded source lines to check ($sourced)"
else
  bad "found unguarded source lines to check" \
      "zero matched — either .zshrc changed shape or the grep broke; this check was vacuous"
fi

summary
