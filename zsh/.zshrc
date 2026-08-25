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
export PATH="$HOME/.rd/bin:$PATH"          # Rancher Desktop
export PATH="$HOME/.local/bin:$PATH"

# Docker Desktop completions. Placed here so oh-my-zsh's single compinit sees
# them; Docker's installer appends a SECOND `compinit` at the end of the file.
#
# That second call was recorded here as costing ~190 ms per shell. Re-taken on
# 2026-08-25 with `measure/compare.sh` (zsh-bench, three runs) it is not a cost
# at all, it is a TRADE: +15.9 ms of first_prompt_lag, -50.6 ms of
# first_command_lag, +16.4 ms of exit_time. The work moves from after the
# prompt to before it.
#
# The old figure was not wrong when it was written. `ZSH_DISABLE_COMPFIX=true`
# below landed afterwards and takes ~29 ms of compaudit out of exactly this
# path; a second compinit WITH the security audit is a different animal. The
# number carried no date, so nothing said it had been overtaken.
#
# Still keep the ordering. What is measured above is latency, and latency is
# not the only reason: two compinit calls also rebuild completion state that
# the first one already built. Whether the trade is worth taking deliberately
# is an open question, and it needs a measurement this comment does not have.
[ -d "$HOME/.docker/completions" ] && fpath=("$HOME/.docker/completions" $fpath)

# ── 2. oh-my-zsh ────────────────────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"

# No theme: Starship draws the prompt (see the Prompt block). Loading a theme
# here and then letting `starship init` overwrite it means paying for two
# prompt engines and using one.
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

# ── 3. Aliases ──────────────────────────────────────────────────────────────
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

  # Destructive, so it lives behind the same guard — for the opposite reason.
  # The shadows above are guarded to stop an agent inheriting a WRONG command;
  # this one is guarded to stop an agent inheriting a DESTRUCTIVE one. `gogc`
  # wipes ~4.6 GB of module cache and ~3.6 GB of build cache, and everything it
  # deletes must be downloaded or compiled again.
  #
  # Only the module cache needs it. `go help cache`: "The go command
  # periodically deletes cached data that has not been used recently" — the
  # BUILD cache already prunes itself. The module cache has no pruning at all,
  # no TTL and no size cap (`go env` exposes only GOCACHE, GOCACHEPROG and
  # GOMODCACHE), and `go clean -modcache` removes the entire thing or nothing.
  # It is also not urgent: counted by download month, the cache grew in two
  # bursts (155 zips in 2026-06, 143 in 2026-07) and a handful in the others —
  # so this is a command you run when the disk is tight, not on a timer.
  alias gogc='go clean -modcache && go clean -cache'
fi

# ── 4. Claude Code ──────────────────────────────────────────────────────────
# Claude Code inherits the shell environment, so these belong here rather than
# in ~/.claude/settings.json — that file is rewritten at runtime by /config and
# /permissions, so a versioned copy of it would fight the tool.
#
# NOT set here: CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN. It forces the classic
# renderer, and it also makes /tui refuse to switch — so it silently locks you
# out of fullscreen. Fullscreen is the richer mode: /focus, click-to-expand tool
# results, flat memory in long conversations, and scrollback that survives
# compaction. Native search and selection are recoverable on demand (Ctrl+o then
# `[`, or hold Shift while dragging). See docs/claude-code-tuning.md.

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

# ── 5. Prompt ───────────────────────────────────────────────────────────────
# The right-hand prompt (right_format in starship.toml) needs this: without it
# zsh reserves an extra column at the edge and the alignment drifts.
# Source: starship.rs/advanced-config
ZLE_RPROMPT_INDENT=0
eval "$(starship init zsh)"

# ── 6. fzf ──────────────────────────────────────────────────────────────────
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# ── 7. zoxide ───────────────────────────────────────────────────────────────
# Interactive only: it replaces `cd` itself, and a script or agent doing
# `cd /abs/path` must get the builtin.
if [[ $- == *i* ]]; then
  eval "$(zoxide init zsh --cmd cd)"
fi

# ── 8. autosuggestions, then syntax-highlighting LAST ───────────────────────
source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
# Must be the final source in this file: it wraps the ZLE widgets every earlier
# plugin registered.
source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
