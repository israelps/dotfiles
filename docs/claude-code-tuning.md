# Tuning Claude Code

Settings measured against 254 real sessions, not guessed. Includes the ones the
measurement said **not** to change — that half is the useful half.

## Where each setting belongs, and why

Claude Code reads configuration from several layers. Two of them matter here:

| Layer | Versioned here? | Why |
|---|---|---|
| Shell environment (`export VAR=…` before `claude`) | **yes**, in `zsh/.zshrc` | documented mechanism; the tool inherits the environment |
| `~/.claude/settings.json` | **no** | rewritten at runtime by `/config` and `/permissions` |
| `~/.claude/rules/*.md` | **yes**, in `claude/` | portable knowledge, does not change on its own |

The `settings.json` exclusion is not caution, it is a known conflict: the
`ryoppippi/dotfiles` repo documents it in its own installer —
`/permissions appends allow rules, /config stores UI preferences` — and merges
the file instead of linking it. Putting the variables in the shell sidesteps
the problem rather than managing it.

## Applied

### `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1`

Fullscreen rendering uses the terminal's **alternate screen buffer**. Inside a
Claude Code session that buffer replaces native scrollback, so everything this
repo configures in the terminal stops working: no scrollback search, no
`jump_to_prompt` (`super+↑/↓`), no triple-click to select a command's output.

The documented benefit of fullscreen is for *"terminal emulators where
rendering throughput is a bottleneck, such as VS Code, tmux, and iTerm2"*.
Ghostty is GPU-accelerated and is not one of them.

Revert: unset the variable and run `/tui fullscreen`.

### `BASH_DEFAULT_TIMEOUT_MS=300000`

Measured over 12,874 calls that passed no explicit timeout:

| Limit | Covers | Falls outside |
|---|---|---|
| 120s (the default) | 99.70% | 38 calls |
| **300s (chosen)** | **99.96%** | **5 calls** |
| 600s | 99.97% | 4 calls |

17 calls actually timed out, and 899 (6.5%) had to carry an explicit timeout
that the agent needed to remember to set. The curve is flat past 300s, so
longer buys almost nothing while making a genuine hang cost five minutes
instead of two.

## Measured and rejected

### `MAX_MCP_OUTPUT_TOKENS` — leave it alone

MCP output is capped at 25,000 tokens with a warning at 10,000. Raising it looks
obvious. Across 254 sessions:

| | Calls |
|---|---|
| Above the 10k warning | **1** |
| Above the 25k cap (truncated) | **0** |

The heaviest MCP tool had a median of 5,655 tokens per call — comfortably under.
Raising a limit you never reach adds risk and buys nothing.

### Raising the terminal scrollback — unnecessary

Ghostty defaults to 10 MB. The busiest session in the sample produced 5.9 MB of
tool output. **Zero** sessions would have overflowed.

## Still open

**Output volume, not failures, is the larger cost.** The same sessions carried
~9 M tokens of tool output: Bash 44.6%, `Read` 18.9%, MCP tools the rest. A
proxy that compresses Bash output (see `rtk`) reaches under half of that, since
built-in tools bypass it by design. Nothing here addresses it yet, and no
number in this repo should suggest otherwise.

Run `./measure/analyze.py` to see your own profile — it will not match this one.
