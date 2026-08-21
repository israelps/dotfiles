# CLAUDE.md

Terminal environment (Ghostty + zsh + Starship) tuned so AI CLI agents don't
waste turns. Every claim here was measured — see `README.md` for the numbers.

## Commands

```bash
brew bundle          # dependencies
./install.sh         # symlinks via stow (--dry-run to preview)
./verify.sh          # run every property test — do this before proposing a change
stow -D zsh starship ghostty ssh   # undo
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

- Rules scoped to areas: `.claude/rules/` (loaded when you touch matching paths)
- Claude Code memory & rules: https://code.claude.com/docs/en/memory
- Starship config: https://starship.rs/config
- Ghostty config: https://ghostty.org/docs/config/reference
