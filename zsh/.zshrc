# ============================================================================
# ~/.zshrc
#
# The order of the blocks below is a contract, not decoration:
#   - the full fpath must be set BEFORE oh-my-zsh loads (it calls compinit
#     unconditionally, so feeding fpath afterwards forces a second call);
#   - zsh-syntax-highlighting must be the LAST thing sourced (its own
#     INSTALL.md: "must be the last plugin sourced").
#
# Properties this file is expected to hold are executable: ../verify.sh
# ============================================================================

# ── 1. PATH and fpath — BEFORE oh-my-zsh ────────────────────────────────────
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
export PATH="$HOME/.antigravity/antigravity/bin:$PATH"
export PATH="$HOME/.antigravity-ide/antigravity-ide/bin:$PATH"
export PATH="$HOME/.rd/bin:$PATH"          # Rancher Desktop
export PATH="$HOME/.local/bin:$PATH"

# Docker Desktop completions. Placed here so oh-my-zsh's single compinit sees
# them; Docker's installer appends a SECOND `compinit` at the end of the file,
# which cost ~190 ms of compinit/compdump per shell. Don't let it come back.
[ -d "$HOME/.docker/completions" ] && fpath=("$HOME/.docker/completions" $fpath)

# ── 2. oh-my-zsh ────────────────────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"

# No theme: Starship draws the prompt (block 5). Loading a theme here and then
# letting `starship init` overwrite it means paying for two prompt engines and
# using one.
ZSH_THEME=""

# Measured with zprof: the update check cost 127 ms on EVERY shell opened —
# the single largest item in startup. Run `omz update` by hand instead.
zstyle ':omz:update' mode disabled

# Swaps the `compinit -i` (+ compaudit) branch for `-u`. Doesn't remove the
# compinit, but skips the security audit of completion directories (~29 ms).
ZSH_DISABLE_COMPFIX=true

plugins=(git)
source "$ZSH/oh-my-zsh.sh"

# oh-my-zsh ships UNGUARDED aliases of its own:
#   ls   -> ls -G
#   grep -> grep --color=auto --exclude-dir={.bzr,CVS,.git,.hg,.svn,.idea,.tox,.venv,venv}
# The colour is harmless (`auto` disables itself off a tty), but --exclude-dir
# SILENTLY changes what a search finds. An agent grepping inside .git or .venv
# gets an empty result and no hint why — then burns a turn guessing.
# Outside an interactive shell we restore POSIX behaviour.
# Caught by tests/no-posix-shadow.test.sh on its very first run.
if [[ $- != *i* ]]; then
  unalias ls grep egrep fgrep 2>/dev/null
fi

# ── 3. conda (optional) ─────────────────────────────────────────────────────
# Tolerant block: does nothing when miniconda isn't installed. No absolute
# path, so this file stays usable on any machine or username. The previous
# version unconditionally appended a non-existent directory to PATH.
CONDA_ROOT="${CONDA_ROOT:-$HOME/miniconda3}"
if [ -x "$CONDA_ROOT/bin/conda" ]; then
    __conda_setup="$("$CONDA_ROOT/bin/conda" 'shell.zsh' 'hook' 2>/dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__conda_setup"
    elif [ -f "$CONDA_ROOT/etc/profile.d/conda.sh" ]; then
        . "$CONDA_ROOT/etc/profile.d/conda.sh"
    else
        export PATH="$CONDA_ROOT/bin:$PATH"
    fi
    unset __conda_setup
fi

# ── 4. Aliases ──────────────────────────────────────────────────────────────
# Own names: always available, collide with nothing.
alias ll='eza -lah --icons=auto --git'
alias la='eza -a  --icons=auto'
alias lt='eza --tree --icons=auto --level=2'
alias b='bat'
alias rgg='rg'

# Convenience shadows: ONLY when a human is typing.
#
# Agents capture your shell state and replay it in a shell whose $- has no `i`.
# Measured: Claude Code's Bash tool runs with $- = 569JNRXghkl, and an
# unguarded `alias cat=bat` still applied — `cat -v file` then failed, because
# bat has no -v. That is one wasted turn, every time.
#
# `--icons=auto` needs the `=`. Bare `--icons` takes an OPTIONAL value and
# swallows the next word: `ls somedir/` died with
# "invalid value 'somedir/' for '--icons [<WHEN>]'".
#
# `grep` and `curl` are deliberately absent: rg honours .gitignore (results
# vanish silently) and xh reads -s as --style. They are not drop-in.
if [[ $- == *i* ]]; then
  alias ls='eza --icons=auto'
  alias tree='eza --tree --icons=auto'
  alias cat='bat --paging=never'
  # oh-my-zsh defines egrep='grep -E'. Combined with any grep alias that isn't
  # grep, that becomes nonsense — with grep=rg it meant `rg -E`, and -E is
  # --encoding, so `egrep -i x f` died with "unknown encoding: -i", rc=2.
  unalias egrep fgrep 2>/dev/null
fi

# ── 5. Claude Code ──────────────────────────────────────────────────────────
# Claude Code inherits the shell environment, so these belong here rather than
# in ~/.claude/settings.json — that file is rewritten at runtime by /config and
# /permissions, so a versioned copy of it would fight the tool.
#
# DISABLE_ALTERNATE_SCREEN keeps the conversation in the terminal's NATIVE
# scrollback instead of the alternate screen buffer. Without it, everything
# this repo configures in Ghostty is dead inside a Claude Code session: no
# search, no jump_to_prompt (super+arrow), no triple-click to select a
# command's output. Fullscreen exists for terminals where render throughput is
# the bottleneck — the docs name VS Code, tmux and iTerm2. Ghostty is
# GPU-accelerated and is not one of them.
#
# Revert by unsetting this and running `/tui fullscreen`.
export CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1

# Default Bash timeout, raised from 120s. Measured over 12,874 calls that did
# NOT pass an explicit timeout:
#     120s covers 99.70%  ->  38 calls fall outside
#     300s covers 99.96%  ->   5 calls fall outside
#     600s covers 99.97%  ->   4   (the curve is already flat)
# 17 calls actually timed out, and 899 (6.5%) had to carry an explicit timeout
# the agent needed to remember.
#
# The trade is real and 300s is where it balances: a genuinely hung command now
# blocks for five minutes instead of two. Longer buys almost nothing.
export BASH_DEFAULT_TIMEOUT_MS=300000

# ── 6. Prompt ───────────────────────────────────────────────────────────────
# The right-hand prompt (right_format in starship.toml) needs this: without it
# zsh reserves an extra column at the edge and the alignment drifts.
# Source: starship.rs/advanced-config
ZLE_RPROMPT_INDENT=0
eval "$(starship init zsh)"

# ── 7. fzf ──────────────────────────────────────────────────────────────────
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# ── 8. zoxide ───────────────────────────────────────────────────────────────
# Interactive only: it replaces `cd` itself, and a script or agent doing
# `cd /abs/path` must get the builtin.
if [[ $- == *i* ]]; then
  eval "$(zoxide init zsh --cmd cd)"
fi

# ── 9. autosuggestions, then syntax-highlighting LAST ───────────────────────
source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
# Must be the final source in this file: it wraps the ZLE widgets every earlier
# plugin registered.
source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
