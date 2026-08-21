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

### `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` — set, then reversed

This repo shipped it. It was wrong, and the reason it was wrong is worth keeping.

**The argument used:** fullscreen replaces native scrollback, so *"everything
this repo configures in the terminal stops working"*, and the docs name VS Code,
tmux and iTerm2 as the terminals that benefit — Ghostty is GPU-accelerated and
is not one of them.

**Both halves were wrong.** What this repo configures in Ghostty is font, theme,
padding and command-finish notifications — none of which fullscreen touches. And
the VS Code/tmux/iTerm2 line is about *flicker* specifically, which is one of
several benefits. The others do not depend on terminal throughput at all:

| Fullscreen gives | Can a tuned terminal do it? |
|---|---|
| `/focus` — prompt, tool summary with diffstats, response | no, app-level |
| click a collapsed tool result to expand it | no, app-level |
| flat memory in long conversations | no, app-level |
| scrollback that survives repeated compactions | no, app-level |
| `Ctrl+o` transcript with `less`-style `/` search, `n`/`N`, `{`/`}` | no, app-level |
| copy-on-select | yes, but the TUI has it too (`/config` → Copy on select) |

**What is actually given up is recoverable on demand**, which the original entry
missed entirely:

| Lost | Recovery |
|---|---|
| `Cmd+f` over the conversation | `Ctrl+o` then `[` writes the whole conversation into native scrollback |
| native click-drag selection | hold `Shift` while dragging; or `CLAUDE_CODE_DISABLE_MOUSE_CLICKS=1` for always |
| open in an editor | `Ctrl+o` then `v` |

**Ghostty is among the better-supported terminals here.** The docs name it three
times, each time favourably: kitty keyboard protocol so `Cmd+c` copies, wheel
events already amplified so scrolling is not sluggish, and special handling so a
plain click opens a link.

**The second failure mode, which is the expensive one:** the variable does not
merely prefer the classic renderer. With it in the environment, `/tui` refuses to
change anything and reports *"Nothing was changed"* — so the escape hatch the
original entry documented (*"unset the variable and run `/tui fullscreen`"*) does
not work while the variable is still exported. A setting that disables the
command meant to undo it is a trap, not a preference.

**Caveat, stated:** fullscreen is a documented **research preview**. It is the
default for accounts that first used Claude Code on or after 2026-05-06.

Enable with `/tui fullscreen` — it saves the `tui` setting, so no variable is
needed. `/tui default` reverts.


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

### A `keybind` for Shift+Enter — Ghostty needs none

`/terminal-setup` exists because most terminals cannot tell Shift+Enter from
Enter: both arrive as CR, so the newline-in-prompt binding has to be faked with
a keybind that sends `ESC` + `CR`. On Ghostty the command reports there is
nothing to configure.

Verified rather than taken on faith, on Ghostty 1.3.1:
`ghostty +list-keybinds --default` binds `super+enter` and `super+shift+enter`
and **nothing** on `shift+enter` — so the key is never intercepted, it reaches
the application. What makes it distinguishable there is the Kitty keyboard
protocol, which Ghostty implements; its own terminfo entry names it
(`keyprotocol=ghostty:kitty`).

So: **do not add a keybind for it.** One copied from an iTerm2-era setup would
send `ESC` + `CR` on top of a protocol that already reports the key correctly.

No test for this one, deliberately. The property is a *default of Ghostty*, not
a claim this repo makes — `ghostty/.config/ghostty/config` says nothing about
keybinds, and asserting someone else's default would test the vendor, not us.
The line worth defending is the absence, and absence is what this entry records.

## Still open

**Output volume, not failures, is the larger cost.** The same sessions carried
~9 M tokens of tool output: Bash 44.6%, `Read` 18.9%, MCP tools the rest. A
proxy that compresses Bash output (see `rtk`) reaches under half of that, since
built-in tools bypass it by design. Nothing here addresses it yet, and no
number in this repo should suggest otherwise.

Run `./measure/analyze.py` to see your own profile — it will not match this one.
