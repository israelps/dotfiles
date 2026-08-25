#!/usr/bin/env bash
# Fetches the INSTRUMENTS this repo's published numbers depend on.
#
# WHY THIS IS SEPARATE FROM install.sh
#   install.sh touches $HOME and never touches the network — that is its
#   contract, and it is why `--dry-run` can promise it changed nothing. This
#   script is the mirror image: it touches the network and never touches $HOME.
#   Keeping them apart means neither one has to be trusted with the other's
#   powers.
#
# WHY NOT THE Brewfile
#   zsh-bench has no formula. `brew search zsh-bench` returns `zsh-async` and
#   nothing else — checked on 2026-08-25. It is a git clone, so the Brewfile
#   could never carry it and tests/deps-installed.test.sh could never see it.
#   That is the exact hole tests/instruments.test.sh now covers.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$DOTFILES_DIR/.instruments"

info() { printf '  %s\n' "$*"; }
erro() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; }

command -v git >/dev/null 2>&1 || { erro "git is required"; exit 1; }

echo "▸ Instruments"
mkdir -p "$DEST"

# --- zsh-bench -------------------------------------------------------------
# Backs README § Prompt choice.
ZSH_BENCH_URL="https://github.com/romkatv/zsh-bench"
# Resolved from upstream HEAD on 2026-08-25. Pinning is not ceremony: an
# instrument that changes under you turns two measurements taken a month apart
# into numbers that were never comparable, and comparing numbers is this repo's
# entire argument. Bump it deliberately, and re-take any number that moves.
ZSH_BENCH_REF="28b1b1bc888159f0a2cf50f9d29381758341aba1"

if [ -x "$DEST/zsh-bench/zsh-bench" ]; then
  have="$(git -C "$DEST/zsh-bench" rev-parse HEAD 2>/dev/null || echo unknown)"
  if [ "$have" = "$ZSH_BENCH_REF" ]; then
    info "zsh-bench already at the pinned commit"
  else
    info "zsh-bench is at $have, re-pinning to $ZSH_BENCH_REF"
    rm -rf "$DEST/zsh-bench"
  fi
fi

if [ ! -x "$DEST/zsh-bench/zsh-bench" ]; then
  info "fetching zsh-bench at $ZSH_BENCH_REF …"
  # init + fetch <sha>, not `clone --depth 1`: clone shallow can only take a
  # branch tip, and a branch tip is precisely what must not be trusted here.
  git init -q "$DEST/zsh-bench"
  git -C "$DEST/zsh-bench" remote add origin "$ZSH_BENCH_URL" 2>/dev/null || true
  git -C "$DEST/zsh-bench" fetch -q --depth 1 origin "$ZSH_BENCH_REF"
  git -C "$DEST/zsh-bench" checkout -q FETCH_HEAD
  info "zsh-bench installed at .instruments/zsh-bench"
fi

# zsh-bench drives a real interactive shell through tmux; without it the tool
# runs and reports nothing useful, which is worse than refusing.
if ! command -v tmux >/dev/null 2>&1; then
  erro "tmux is missing — zsh-bench needs it to drive an interactive shell"
  info "install it with:  brew bundle   (from $DOTFILES_DIR)"
  exit 1
fi

echo
info "instruments ready. Verify with:  ./tests/instruments.test.sh"
