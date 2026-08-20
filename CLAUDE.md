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
5. **Every fix carries a test.** A change to `zsh/`, `starship/`, `ghostty/` or
   `ssh/` without a matching assertion in `tests/` is incomplete.

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
