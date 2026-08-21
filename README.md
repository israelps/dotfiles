# dotfiles

**A terminal whose friction with AI agents was measured, whose fixable causes
were fixed with tests that stop them coming back, and that ships the
measurement tool so you can find yours.**

Ghostty + zsh + Starship on macOS.

```
󰀵  …/my-project    main !?                                        14:32
❯
```

The right column reports what happened, not where you are — exit code, background
jobs, duration, clock.

---

## What this does *not* claim

It does not eliminate agent friction. The measurement says that is not on offer.

Across **254 sessions · 21,637 tool calls · 1,347 failures · 482 rework turns**,
here is where the rework actually came from:

| Cause | Rework turns | Fixable? |
|---|---|---|
| Long tail (582 failures, most common form appeared 18×) | ~409 | no — no lever |
| The owner's own `PreToolUse` guards, denying by design | ~266 | no — that is the system working |
| Permission prompts / rejected calls | ~61 | partly — allowlist |
| MCP invalid or unavailable | ~51 | no |
| Network / remote | ~30 | no |
| Path does not exist | ~27 | no |
| **Alias shadowing a POSIX tool** | **~26** | **yes, entirely** |
| Shell syntax | ~17 | partly |

So the honest scope is small and permanent: **~26 rework turns, gone and
regression-proof** — plus two latency wins found on the way.

---

## What it fixes, with the number behind each

| Fix | Evidence | Result |
|---|---|---|
| Aliases never shadow POSIX outside an interactive shell | 29 failures, 19 sessions | ~26 rework turns eliminated |
| `--icons=auto` (with the `=`) | `ls somedir/` broken 51× | `eza --icons` swallows the next word |
| `unalias egrep fgrep` | `rg -E` is `--encoding` | `egrep -i x f` exited 2 |
| `unalias ls grep` outside interactive | oh-my-zsh leaks `--exclude-dir` | searches stop lying by omission |
| `compinit` once; oh-my-zsh update check off | zprof: 190 ms + 127 ms | startup **0.18–0.28 s → 0.13 s** |
| Prompt spawns no language subprocess | `go version` took 1553 ms with an absent toolchain | warning gone; ~31 ms per prompt |
| **SSH connection multiplexing** | 878 invocations, 487 to one host, 2.4 h | **508 ms → 63 ms, 88%** |
| **Notify on commands over 30 s** | 651 commands > 30 s, 19.5 h waiting | the wait stops being blind |

`ssh` deserves its own note: it was the single largest source of rework
(69 extra turns, 13% failure rate). Most of that cost is connection setup — a
handshake that can fail. A reused socket does not redo the handshake.

---

## What is in this repo, and what is deliberately not

This boundary is the part most dotfiles repos get wrong.

| Stays OUTSIDE — private, never versioned | Lives HERE — generic, safe to publish |
|---|---|
| `~/.ssh/config` — your hosts, users, key paths | `ssh/.ssh/config.d/10-multiplex.conf` — no host appears in it |
| `.claude/settings.local.json` — your allowlist, which reveals how you work | `.claude/settings.json.example` — a template |
| `~/.claude/projects/**` — your transcripts | `measure/analyze.py` — reads them locally, sends nothing |
| `~/.claude/settings.json` — model, plugins, status line, and rewritten at runtime by `/config` | `claude/.claude/rules/` — portable knowledge, plus the env vars in `zsh/.zshrc` |
| Credentials, in `.env` or a password manager | `.gitignore` blocking the known patterns |

**One manual step** the installer cannot do for you, because the file is yours.
Add this at the **top** of `~/.ssh/config` — order matters, ssh takes the first
value it obtains for each parameter:

```sshconfig
Include ~/.ssh/config.d/*.conf
```

`tests/ssh-multiplex.test.sh` fails if a host-specific directive ever appears in
a published fragment.

---

## It tunes Claude Code too, from the same place

Claude Code inherits the shell environment, so its settings live in
`zsh/.zshrc` rather than in `~/.claude/settings.json` — that file is rewritten
at runtime by `/config` and `/permissions`, so a versioned copy would fight the
tool.

| Variable | Measured reason |
|---|---|
| `BASH_DEFAULT_TIMEOUT_MS=300000` | 120s covered 99.70% of 12,874 calls, leaving 38 outside; 300s leaves 5, and the curve is flat past that |

And two it deliberately does **not** set.

`CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` shipped here once and was reversed. It
forces the classic renderer and, worse, makes `/tui` refuse to switch — so it
silently locks you out of fullscreen, including the escape hatch meant to undo
it. Fullscreen carries `/focus`, click-to-expand tool results, flat memory in
long conversations and scrollback that survives compaction; what it gives up is
recoverable on demand (`Ctrl+o` then `[` for native search, `Shift`+drag for
native selection). Full account, including the argument that was wrong, in
[docs/claude-code-tuning.md](docs/claude-code-tuning.md).

The other is `MAX_MCP_OUTPUT_TOKENS`. Raising the
25k cap looks obvious, but across 254 sessions exactly **one** call passed the
10k warning and **none** hit the cap.

Details, including what is still unaddressed: [`docs/claude-code-tuning.md`](docs/claude-code-tuning.md)

## Properties, executable

Documentation rots. These do not:

```bash
./verify.sh
```

| Suite | Property |
|---|---|
| `no-posix-shadow` | no alias shadows POSIX outside an interactive shell, while interactive convenience is preserved |
| `args-survive` | every alias still works when handed an argument |
| `exit-codes` | failures report non-zero, and nothing opens a pager that would block an agent |
| `prompt-no-hang` | the prompt spawns no unbounded subprocess and emits no warning |
| `ssh-multiplex` | connections are reused, the socket path survives the ~104-byte limit, and no host leaks into a fragment |
| `repo-hygiene` | the repo publishes what it means to and nothing it does not, and no tracked file carries a personal absolute path |
| `deps-installed` | `brew bundle check` passes, every formula the Brewfile declares is installed, and every unguarded `source` in `.zshrc` resolves |

The suite earned its keep on its first run: it caught oh-my-zsh's own unguarded
`ls` and `grep` leaking into non-interactive shells — a leak neither the author
nor the assistant knew about.

It also guards against itself. An unexpected shell error fails the run instead
of reporting a vacuous green, verified by injecting a `mapfile` call that macOS
bash 3.2 does not have. Everything in `tests/` runs on the OS bash.

---

## Measure your own

Your friction profile is not this one.

```bash
./measure/analyze.py
```

It counts **rework** — a failure the agent absorbs costs one turn; one that
triggers three retries costs four — plus output volume by tool and command
duration. See [`measure/README.md`](measure/README.md), including the notice
that it reads private transcripts locally.

---

## Install

```bash
git clone https://github.com/israelps/dotfiles ~/projects/dev/dotfiles
cd ~/projects/dev/dotfiles
brew bundle
./install.sh          # --dry-run to preview
./verify.sh           # prove the properties hold on your machine
```

Open a new terminal. Undo with `stow -D zsh starship ghostty ssh`.

---

## Things that sound right and measured wrong

Half the value of measuring is what it stops you building:

| Common advice | What the measurement said |
|---|---|
| *"install Rust to speed up the terminal"* | Starship **is** a Rust binary. Installing the toolchain only activates `[rust]`, adding a subprocess per prompt |
| *"`git core.fsmonitor` speeds up the prompt"* | **slower** on a small repo: 15.55 → 24.75 ms. It is built for 100k+ files |
| *"lower `command_timeout` for a snappier prompt"* | modules run **in parallel**; a tight ceiling speeds nothing and makes modules vanish with a warning |
| *"`time zsh -i -c exit` measures shell speed"* | it times the process **exiting**, not the prompt appearing |
| *"strip colour and icons so agents read cleanly"* | ANSI is **0.24%** of 16 M characters; `--color=auto` already disables itself off a tty |
| *"raise the scrollback for long agent sessions"* | busiest session produced 5.9 MB against a 10 MB default — **zero** sessions would overflow |
| *"bind a key to jump between prompts"* | already bound: `super+↑/↓` |
| *"compress output losslessly"* | **~0%** — dense output has nothing to squeeze |

---

## Prompt choice

Measured with [`zsh-bench`](https://github.com/romkatv/zsh-bench), 2 runs × 16 iterations:

| | `first_prompt_lag` | `command_lag` | `input_lag` |
|---|---|---|---|
| Powerlevel10k | **135 ms** | 17 ms | 12.4 ms |
| **Starship** (chosen) | 344 ms | 77 ms | **9.2 ms** |
| Pure | 285 ms | **12 ms** | 9.5 ms |
| Spaceship | 377 ms | 99 ms | 9.7 ms |

Starship is **not** the fastest — p10k renders asynchronously and has an instant
prompt. The choice was deliberate: readable TOML and looks, for ~60 ms per
command. **If latency is your criterion, use Powerlevel10k or Pure.** This repo
gives you the numbers, not a rooting interest.

---

## Structure

```
dotfiles/
├── README.md · CLAUDE.md          # humans · agents (2 screens, per the docs)
├── .claude/
│   ├── settings.json.example
│   └── rules/{shell,tests}.md     # paths:-scoped, load only where they apply
├── claude/.claude/rules/           # portable user-level rules
├── docs/claude-code-tuning.md
├── measure/analyze.py
├── tests/                          # lib.sh + 7 suites
├── install.sh · verify.sh · Brewfile
├── zsh/ · starship/ · ghostty/ · ssh/
└── .github/workflows/gitleaks.yml
```

Every file carries, in comments, the measured reason for each choice.

## Security

Public repo, **no secrets** — not even encrypted. [`.gitignore`](.gitignore)
blocks the known patterns; CI runs [gitleaks](https://github.com/gitleaks/gitleaks)
over the full history; `.githooks/pre-commit` catches them earlier. No absolute
user paths in tracked files.

If you adopt this: **rotate your keys first**, not after.

## Credits

[Starship](https://starship.rs) · [Ghostty](https://ghostty.org) ·
[GNU Stow](https://www.gnu.org/software/stow/) ·
[zsh-bench](https://github.com/romkatv/zsh-bench)

## License

[MIT](LICENSE)
