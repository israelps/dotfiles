# Branch work when the working tree is the live config

`~/.zshrc`, `~/.config/starship.toml`, `~/.config/ghostty/config` and
`~/.ssh/config.d/*.conf` are stow symlinks into this checkout. Git operations
that rewrite the working tree therefore rewrite the machine's configuration.

## What changes, and when

Not "in real time" uniformly — the blast radius differs per file, and the quiet
ones are the dangerous ones.

| File | When a branch change reaches you |
|---|---|
| `starship/.config/starship.toml` | **immediately** — Starship is a new process every prompt |
| `ssh/.ssh/config.d/*.conf` | **immediately** — ssh reads its config per invocation |
| `zsh/.zshrc` | next shell: a new tab, a new agent session, a new script |
| `ghostty/.config/ghostty/config` | next window or reload |
| `claude/.claude/rules/*.md` | next agent session |

The shell you are sitting in does not change, which is exactly why this is easy
to miss. The next agent session inherits whatever the branch says.

The worst case is not a branch change at all: a merge conflict leaves
`<<<<<<<` inside `.zshrc`, and every new shell then opens on a syntax error.
That is why `CLAUDE.md` prescribes `merge --ff-only`.

## The workflow

```bash
git wt new fix/ghostty-blur      # ../dotfiles-wt/fix/ghostty-blur, branched off main
cd ../dotfiles-wt/fix/ghostty-blur
# … work, commit …
./verify.sh                      # file properties run; live ones say SKIP
cd -                             # back to the main checkout
git wt promote fix/ghostty-blur  # merge --ff-only, remove the worktree, verify
```

`git wt` is a repo-**local** alias for `./tools/wt.sh`, set by `./install.sh`.
Without it, call the script directly — it behaves identically.

| Command | What it does |
|---|---|
| `git wt new <branch>` | `git worktree add -b <branch> ../<repo>-wt/<branch> main` |
| `git wt list` | every worktree, tagged dirty / merged / locked |
| `git wt clean` | lists what it *would* remove, and stops |
| `git wt clean --yes` | removes them, deletes the merged branch, prunes empty dirs |
| `git wt promote <branch>` | ff-only merge → remove worktree → delete branch → `verify.sh` |

**Only `list` runs from inside a worktree.** Everything that mutates must run
from the main checkout, because a `!`-prefixed git alias executes from the top
of the *active* worktree — so `git wt` typed on a branch runs *that branch's*
copy of the script.

### Removable, for `clean`

A worktree is removed only when its branch is merged into `main`, its tree is
clean, and it is not locked. Anything else is listed with the reason it was
kept. Git ships no reaper for this: `git worktree prune` only clears metadata
for directories that already vanished, and `git gc` waits three months
(`gc.worktreePruneExpire`).

## What backs this up

**`install.sh` refuses to run from a linked worktree.** Running it there would
point `$HOME` at a branch. This was not theoretical: during development, the
pre-guard `install.sh` run from a worktree reported a bogus conflict on
`~/.ssh/config.d/10-multiplex.conf` — the first symptom of it preparing to
re-link everything at the branch.

**`.githooks/post-checkout` is a siren.** It fires when *this* checkout leaves
`main`, and six rules keep it from crying wolf — the hook numbers them in the
same order:

1. a path checkout (`git restore`, `git checkout -- file`);
2. a null old-ref, which means the checkout *created* this tree (`git clone`,
   `git worktree add`);
3. a linked worktree, where changing branches is the whole point;
4. a rebase or bisect in progress;
5. landing back on `main`, which is the cure;
6. any clone that is not the stowed one — this is a public repo, and an alarm
   about a live config the reader does not have is noise that makes the real
   one less credible.

There is **no `pre-checkout` hook in git**, so it can only warn after the fact,
and its exit status becomes `git switch`'s — hence the explicit `exit 0`.

**It cannot see half of invariant 6.** `git stash`, `git reset --hard`,
`git merge`, `git pull` (merge) and `stow -D` all change the live config and
fire no `post-checkout` at all. `git rebase` *does* fire it, "by accident of
implementation" per `git-rebase(1)`, which is why rebase and bisect are
explicitly silenced.

**The suites tell a file property from a live one.** `tests/checkout-state.sh`
classifies the checkout as `stowed`, `worktree` or `absent`:

| State | Meaning | Live checks |
|---|---|---|
| `stowed` | `$HOME/.zshrc` **is** this checkout's file | run |
| `worktree` | a linked worktree of the checkout that *is* stowed | `SKIP`, labelled |
| `absent` | anything else — stow never ran, unrelated clone | **run, so they fail** |

`absent` never skips, and `worktree` requires positive proof that the live file
belongs to *this repository's* main worktree. Without that proof a linked
worktree of an unrelated clone would earn a permanent free pass — a green suite
on a machine nothing was installed on.

Three states, but five cases, and `tests/worktree.test.sh` drives every one
against a hermetic fixture with a fake `$HOME`: a stowed checkout, a worktree
of it, an unrelated clone, **a worktree of an unrelated clone**, and a machine
stow never touched. The last four must all come back `absent` or `worktree`
exactly as listed — and two of them are cases this machine can never produce,
which is why the fixture exists at all.

Identity is `device:inode`, never a resolved path: macOS ships neither
`realpath(1)` nor `readlink -f`.

## Gotchas worth knowing

**`.claude/settings.local.json` is gitignored**, so `git worktree add` does not
bring it — every agent command in a fresh worktree would stop for a permission
prompt. `git wt new` symlinks it from the main checkout. A symlink and not a
copy: a copy drifts, and drift in an allowlist is a permission you believed you
had revoked.

**A worktree checks out `HEAD`, not your working tree.** Uncommitted work in
the main checkout does not appear there. This bites when testing changes to
`install.sh` or the hooks themselves.

**Branch names with `/` nest** — `feat/x` becomes `../dotfiles-wt/feat/x`.
`clean` and `promote` remove the emptied parent directories afterwards.

**`git branch -d`, never `-D`.** Git refuses to delete an unmerged branch, so
git itself is the guard rather than this repo's own merged check.
