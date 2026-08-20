# Dependencies for this environment. Install with:  brew bundle
#
# Every entry has a measured reason — see README.md § Measurements.

# ── Terminal and prompt ─────────────────────────────────────────────────────
cask "ghostty"                    # GPU-accelerated, injects zsh shell integration itself
brew "starship"                   # prompt (already a Rust binary — see README § myths)

# ── Shell ───────────────────────────────────────────────────────────────────
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"    # MUST be sourced last — see zsh/.zshrc block 8
brew "stow"                       # the symlink manager this repo uses

# ── Modern CLI tools ────────────────────────────────────────────────────────
# None of these shadows a POSIX binary without an interactivity guard.
# The reason is the whole point of this repo — see README § The problem.
brew "eza"                        # ls
brew "bat"                        # cat
brew "ripgrep"                    # grep  (exposed as `rgg`, NEVER as `grep`)
brew "fd"
brew "fzf"
brew "zoxide"                     # smarter cd (interactive shells only)
brew "xh"                         # curl-like (exposed as `xh`, NEVER as `curl`)

# ── Verification ────────────────────────────────────────────────────────────
brew "shellcheck"                 # install.sh and tests/ are kept shellcheck-clean
brew "gitleaks"                   # pre-commit secret scan
brew "tmux"                       # required by zsh-bench, if you want to measure
