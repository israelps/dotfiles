---
paths: ["zsh/**", "ssh/**"]
---

# Shell and SSH

Loaded only when you touch `zsh/` or `ssh/`.

## The interactivity split

Convenience that changes a command's behaviour goes inside `[[ $- == *i* ]]`.
Anything outside it applies to scripts, CI and agents too.

Measured on the machine this repo came from: Claude Code's Bash tool runs with
`$-` = `569JNRXghkl` — no `i` — and an unguarded `alias cat=bat` still applied.
`cat -v file` then failed, because `bat` has no `-v`.

**Never shadow `grep` or `curl`**, not even guarded. `rg` honours `.gitignore`,
so a search comes back empty with no explanation; `xh` reads `-s` as `--style`.
Expose them under their own names (`rgg`, `xh`).

Watch for flags that take an OPTIONAL value: `eza --icons` swallows the next
word, so `ls somedir/` fails. Always `--icons=auto`, with the `=`.

## oh-my-zsh leaks

oh-my-zsh defines its own unguarded `ls` and `grep`. Its
`grep --exclude-dir={.git,.venv,…}` silently changes what a search finds. The
`.zshrc` unaliases them outside interactive shells; keep that block.

## SSH

`ssh/.ssh/config.d/*.conf` holds only generic fragments. Host-specific settings
— `HostName`, `User`, `IdentityFile`, `Port` — stay in `~/.ssh/config`, which is
never versioned. `tests/ssh-multiplex.test.sh` fails if a host directive appears
in a fragment.

`ControlPath` must use `%C`, not `%r@%h:%p`: a Unix socket path is capped near
104 bytes and the readable form overflows it.

## Order in .zshrc

`fpath` complete before `source oh-my-zsh.sh` (it calls `compinit`
unconditionally — feeding fpath afterwards forces a second call, ~190 ms).
`zsh-syntax-highlighting` is the last source in the file: it wraps ZLE widgets
every earlier plugin registered.

Reference: https://code.claude.com/docs/en/memory
