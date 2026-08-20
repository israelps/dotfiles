#!/usr/bin/env bash
# Installs the dotfiles by creating symlinks via GNU Stow.
# Idempotent: running it twice is harmless. Nothing is overwritten silently.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES=(zsh starship ghostty ssh claude)
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help)
      echo "usage: $0 [--dry-run]"
      echo "  --dry-run   show what would happen, without touching the filesystem"
      exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

info() { printf '  %s\n' "$*"; }
erro() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; }

# ── 1. Dependências ─────────────────────────────────────────────────────────
echo "▸ Checking dependencies"
missing_bins=()
for bin in stow zsh starship; do
  command -v "$bin" >/dev/null 2>&1 || missing_bins+=("$bin")
done
if [ ${#missing_bins[@]} -gt 0 ]; then
  erro "missing: ${missing_bins[*]}"
  info "install them with:  brew bundle   (from $DOTFILES_DIR)"
  exit 1
fi
info "ok — stow, zsh and starship are present"

# ── 2. Conflitos ────────────────────────────────────────────────────────────
# A REAL file (not a symlink) at the destination would either be swallowed by
# stow --adopt or make stow abort. Better to detect it and say so up front.
echo "▸ Looking for conflicts"
conflicts=0
while IFS= read -r src; do
  dest="$HOME/${src#*/}"
  [ -e "$dest" ] || continue
  # Already ours? Stow folds trees: it may symlink a whole DIRECTORY, so the
  # file inside is not itself a symlink even though it resolves into the repo.
  # Comparing resolved paths is the only check that survives tree folding —
  # `[ -L "$dest" ]` alone reports a false conflict. Found by dogfooding.
  real_dest="$(cd "$(dirname "$dest")" 2>/dev/null && pwd -P)/$(basename "$dest")"
  real_src="$DOTFILES_DIR/$src"
  [ "$real_dest" = "$real_src" ] && continue
  if [ ! -L "$dest" ]; then
    erro "exists and is NOT a symlink: $dest"
    conflicts=$((conflicts + 1))
  fi
done < <(cd "$DOTFILES_DIR" && find "${PACKAGES[@]}" -type f -not -name '.DS_Store')

if [ "$conflicts" -gt 0 ]; then
  erro "$conflicts conflict(s). Move or delete the files above, then run again."
  info "to import them into the repo instead of deleting:  stow --adopt ${PACKAGES[*]}"
  info "(--adopt OVERWRITES the repo content with your \$HOME copy — check git diff afterwards)"
  exit 1
fi
info "ok — no real file would be overwritten"

# ── 3. Directories the config needs to exist ────────────────────────────────
# ssh refuses a control socket in a directory others can enter, and it will not
# create the directory itself.
if [ ! -d "$HOME/.ssh/cm" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    info "would create ~/.ssh/cm (0700)"
  else
    mkdir -p "$HOME/.ssh/cm" && chmod 700 "$HOME/.ssh/cm"
    info "created ~/.ssh/cm (0700)"
  fi
else
  chmod 700 "$HOME/.ssh/cm" 2>/dev/null || true
  info "\$HOME/.ssh/cm ok"
fi

# ── 4. Symlinks ─────────────────────────────────────────────────────────────
echo "▸ Creating symlinks"
stow_flags=(-v -d "$DOTFILES_DIR" -t "$HOME")
[ "$DRY_RUN" -eq 1 ] && stow_flags+=(-n)
stow "${stow_flags[@]}" "${PACKAGES[@]}"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "▸ Dry run — nothing was modified."
  exit 0
fi

# ── 5. Verification ──────────────────────────────────────────────────────────
echo "▸ Verifying"
zsh -n "$DOTFILES_DIR/zsh/.zshrc" && info ".zshrc syntax ok"
if starship prompt >/dev/null 2>&1; then
  info "starship renders ok"
else
  erro "starship failed to render — check ~/.config/starship.toml"
fi

echo
echo "Done. Open a NEW terminal — the current one still has the old config."
echo
echo "ONE MANUAL STEP — ~/.ssh/config is yours and is never versioned."
echo "Add this line at the TOP of it (order matters: ssh takes the FIRST value"
echo "it obtains for each parameter):"
echo
echo "    Include ~/.ssh/config.d/*.conf"
echo
echo "Then check it took effect:  ssh -G <any-host> | grep controlmaster"
