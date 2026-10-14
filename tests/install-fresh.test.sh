#!/usr/bin/env bash
# PROPERTY: install.sh, on a machine that is not the owner's, either succeeds or
# stops before any plan with a remedy that works when pasted.
#
# WHY THIS MATTERS
#   Every other suite runs on a machine that already has this config, so none of
#   them can see a first install. An audit on 2026-10-14, before the repo went
#   public, found three things that only a fresh machine trips over:
#     - zsh/.zshrc sources oh-my-zsh unguarded, and nothing installed it or said
#       it was needed — every new shell would open with an error;
#     - everybody already has a ~/.zshrc, so the first run always hits a
#       conflict, and the only remedy offered was `stow --adopt`, which
#       overwrites the repo with the user's file;
#     - claude/ was linked unasked, putting a rule into ~/.claude/rules/ that
#       assumes an MCP server the new machine may not have.
#
#   The fixture is a COPY of the working tree, not a clone: a clone carries the
#   committed install.sh, so on a branch the suite would test the old script.
#   No git in the copy also means install.sh skips its checkout and repository
#   steps — the shape of a downloaded tarball. Everything runs --dry-run with
#   $HOME pointed at the fixture, so nothing outside it is written.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "▸ install.sh on a fresh machine"

for bin in stow zsh starship; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "  SKIP  $bin not installed — install.sh stops on it before anything under test"
    exit 0
  fi
done

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/repo" "$FIX/home"
cp "$DOTFILES_DIR/install.sh" "$FIX/repo/"
for pkg in zsh starship ghostty ssh claude; do cp -R "$DOTFILES_DIR/$pkg" "$FIX/repo/"; done

# _install [args...] -> combined output in $out, exit code in $rc.
_install() {
  rc=0
  out="$(env HOME="$FIX/home" "$FIX/repo/install.sh" --dry-run "$@" 2>&1)" || rc=$?
}

# ── a. no oh-my-zsh: refuse, name it, before any plan ─────────────────────────
_install
assert_fails "refuses without oh-my-zsh" test "$rc" -eq 0
case "$out" in
  *"git clone https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh"*)
       ok "names the command that installs oh-my-zsh" ;;
  *)   bad "names the command that installs oh-my-zsh" "output: $out" ;;
esac
case "$out" in
  *"Creating symlinks"*) bad "refuses before printing any plan" "a plan was printed: $out" ;;
  *)                     ok "refuses before printing any plan" ;;
esac

# ── b. control: oh-my-zsh present, empty $HOME — the answer is known: success ─
mkdir -p "$FIX/home/.oh-my-zsh"
: > "$FIX/home/.oh-my-zsh/oh-my-zsh.sh"
_install
assert_eq "a clean machine with oh-my-zsh installs (dry run)" 0 "$rc"

# ── c. a real ~/.zshrc: refuse, and the printed remedy must work ──────────────
printf '# the new user'"'"'s own config\n' > "$FIX/home/.zshrc"
_install
assert_fails "refuses when ~/.zshrc is a real file" test "$rc" -eq 0
remedy="$(printf '%s\n' "$out" | sed -n -E 's/^ +(mv ~\/.*)$/\1/p')"
if [ -n "$remedy" ]; then
  ok "prints a ready-to-paste backup line: $remedy"
  # Run the EXACT lines it printed, with the fixture as $HOME, then try again.
  while IFS= read -r line; do
    env HOME="$FIX/home" bash -c "$line" || true
  done <<< "$remedy"
  _install
  assert_eq "after running the printed remedy, the install proceeds" 0 "$rc"
  if [ -f "$FIX/home/.zshrc.pre-dotfiles" ]; then
    ok "the user's own ~/.zshrc survived as ~/.zshrc.pre-dotfiles"
  else
    bad "the user's own ~/.zshrc survived as ~/.zshrc.pre-dotfiles" "no backup file found"
  fi
else
  bad "prints a ready-to-paste backup line" "no 'mv ~/…' line in: $out"
fi

# ── d. claude/ only on request ────────────────────────────────────────────────
# stow -n -v reports each planned link as `LINK: <target> => <source>`. The
# .zshrc link is asserted in the SAME output, so an absent .claude link cannot
# be a parse that matched nothing.
_install
case "$out" in *"LINK: .zshrc"*) ok "the default plan links ~/.zshrc" ;;
                *) bad "the default plan links ~/.zshrc" "output: $out" ;; esac
case "$out" in *"LINK: .claude"*) bad "the default plan leaves ~/.claude alone" "output: $out" ;;
                *) ok "the default plan leaves ~/.claude alone" ;; esac
_install --with-claude
case "$out" in *"LINK: .claude"*) ok "--with-claude links ~/.claude" ;;
                *) bad "--with-claude links ~/.claude" "output: $out" ;; esac

summary
