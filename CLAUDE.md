# CLAUDE.md

Terminal environment (Ghostty + zsh + Starship) tuned so AI CLI agents don't
waste turns. Every claim here was measured — see `README.md` for the numbers.

## Commands

```bash
brew bundle          # dependencies
./install.sh         # symlinks via stow (--dry-run to preview; --with-claude adds claude/)
./verify.sh          # run every property test — do this before proposing a change
stow -D zsh starship ghostty ssh   # undo (add claude if it was installed)
```

## Invariants — do not break these

1. **No alias shadows a POSIX command outside an interactive shell.** Agents
   inherit your shell state in a shell whose `$-` has no `i`. Convenience
   shadows live inside `if [[ $- == *i* ]]`. `grep` and `curl` are never
   shadowed at all: `rg` honours `.gitignore` and `xh` has an incompatible CLI.
2. **The prompt runs no unbounded subprocess.** Native Starship language
   modules shell out per prompt; they stay disabled. The one command the prompt
   does run is bounded by construction (`GOTOOLCHAIN=local`, which cannot reach
   the network).
3. **Order in `zsh/.zshrc` is a contract.** Full `fpath` before oh-my-zsh (it
   calls `compinit` unconditionally); `zsh-syntax-highlighting` sourced last.
4. **No secret, and no absolute user path, in a tracked file.** Use `$HOME`.
5. **Every fix carries a test.** A change to `zsh/`, `starship/`, `ghostty/`,
   `ssh/` or `Brewfile` without a matching assertion in `tests/` is incomplete.
   A formula you add to `Brewfile` also needs a probe in
   `tests/deps-installed.test.sh` — that suite fails on any entry it cannot see.
6. **The working tree IS the live config.** `~/.zshrc` and friends are symlinks
   into this repo, so `git switch`, `checkout`, `stash` and `stow -D` change the
   running shell — they are not inert here. Leave the repo on `main`; if work
   goes to a branch, merge it back in the same sitting. A branch left checked
   out is a shell configured by whatever that branch happens to say.
   **Do branch work in a linked worktree instead** — `git wt new <branch>`
   puts it in `../dotfiles-wt/<branch>`, where nothing under `$HOME` points,
   and `git wt promote <branch>` merges it back and removes it. `install.sh`
   refuses to run from a worktree, and `.githooks/post-checkout` warns if this
   checkout ever leaves `main` — a siren, not a barrier: `git stash`,
   `git reset --hard`, `git merge` and `stow -D` fire no hook at all.
   Full account: `docs/worktree-workflow.md`.

   **The live surface is the stow packages, and nothing else.** A save inside
   `zsh/`, `starship/`, `ghostty/`, `ssh/` or `claude/` is live before any git
   command runs — no commit, no switch, no hook involved. Everything else
   (`tests/`, `docs/`, `measure/`, `tools/`, `README.md`, `.claude/`) is
   ordinary source: edit it on `main`.

   | Touching | Where to work |
   |---|---|
   | a stow package | `git wt new <branch>` → edit → `./measure/compare.sh` if it could affect latency → `./verify.sh` → commit there → `git wt promote` |
   | anything else | `main`, directly |

   `.claude/hooks/` enforces this for the agent. Each script answers one
   question — three before the call, one net after:

   | script | asks |
   |---|---|
   | `guard-live-edit.sh` | is this **path** live? (`Edit`/`Write`) |
   | `guard-live-write.sh` | does this **command** write somewhere live? (`Bash`) |
   | `guard-git.sh` | does this command **replace the tree**? (`Bash`) |
   | `guard-live-drift.sh` | did the live surface **move anyway**? (`PostToolUse`) |

   The first three refuse before anything happens but read intent, so they are
   blind to an edit hosted by an interpreter (`python3 -c`, `perl -i`) or a path
   built at runtime. The fourth asks git instead, which cannot be fooled — at
   the cost of being one tool call late. `session-start.sh` snapshots the
   surface at turn zero so the net reports only what THIS session moved; your
   own uncommitted work is its floor, never its accusation. `git switch main`
   is always allowed — it is the cure. The bound is real: these constrain the
   agent, never the owner typing in their own terminal.
   Driven by `tests/claude-hooks.test.sh` (hermetic fixture — producing real
   drift here would mean committing the very act under test); wired by
   `./install.sh`, which updates its own wiring and leaves anyone else's alone.

## Handing a command to the owner

Some acts only the owner can run. When you write one for them:

- **One line per act.** A wrapped line pastes as two broken commands. Measured:
  a `git -C <absolute path to this repo> merge --ff-only <branch>` wrapped
  mid-path and ran as `git … merge` (no args) plus `--ff-only …` (command not
  found). Neither half errored in a way that named the real cause.
- **Keep the path short.** `~/projects/dev/dotfiles`, or `cd` first — never the
  absolute path spelled out.
- **Never chain a destructive step to the step that fixes it.** `git switch main
  && git merge …` reverts the live config on the first half; if the second half
  does not run, the owner is worse off than before it was typed.

## What lives outside this repo

| Outside, and why | Inside |
|---|---|
| `~/.ssh/config` — your hosts, users and key paths | `ssh/.ssh/config.d/10-multiplex.conf` (generic) |
| `.claude/settings.local.json` — your allowlist | `.claude/settings.json.example` |
| `~/.claude/projects/**` — private transcripts | `measure/analyze.py`, which reads them locally |

`~/.ssh/config` needs one manual line at the **top** (ssh takes the first value
it obtains): `Include ~/.ssh/config.d/*.conf`

## Before changing anything

Run `./verify.sh`. If you are adding a fix, first show the measurement that
justifies it — `measure/analyze.py` is how this repo decides what is worth
fixing. A change with no number behind it does not belong here.

## Reference

- Rules: `.claude/rules/` — path-scoped ones load when you touch matching
  paths; a rule with no `paths:` is always loaded. Writing one is itself
  governed by `.claude/rules/policy-layer.md`.
- Claude Code memory & rules: https://code.claude.com/docs/en/memory
- Starship config: https://starship.rs/config
- Ghostty config: https://ghostty.org/docs/config/reference
