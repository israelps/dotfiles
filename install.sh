#!/usr/bin/env bash
# Installs the dotfiles by creating symlinks via GNU Stow.
# Idempotent: running it twice is harmless. Nothing is overwritten silently.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Every stow package in this repo. .claude/hooks/lib.sh reads THIS line as the
# definition of the live surface, so it lists all of them — including the
# optional ones below, which are live wherever they happen to be installed.
PACKAGES=(zsh starship ghostty ssh claude)
# Installed only on request. `claude` puts rules into ~/.claude/rules/, which
# changes how YOUR Claude Code behaves in every project — and its one rule
# assumes the Context7 MCP server, which a new machine may not have.
OPTIONAL_PACKAGES=(claude)
DRY_RUN=0
WITH_CLAUDE=0

for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRY_RUN=1 ;;
    --with-claude) WITH_CLAUDE=1 ;;
    -h|--help)
      echo "usage: $0 [--dry-run] [--with-claude]"
      echo "  --dry-run       show what would happen, without touching the filesystem"
      echo "  --with-claude   also link claude/ (Claude Code rules) into ~/.claude"
      exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

info() { printf '  %s\n' "$*"; }
erro() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; }

# ── 0. Am I the main checkout? ──────────────────────────────────────────────
# This script points $HOME at THIS directory. Run from a linked worktree it
# would repoint the live shell at a branch — the exact accident the worktree
# workflow exists to prevent (docs/worktree-workflow.md).
#
# Checked before --dry-run is honoured on purpose: a dry run from the wrong
# directory should say "wrong directory", not print a plausible plan.
#
# The main worktree is the only place --git-dir and --git-common-dir agree.
if git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  # `|| echo ''` on both: `set -e` plus a failing command substitution in an
  # assignment kills the script, and --path-format needs git >= 2.31.
  gd="$(git -C "$DOTFILES_DIR" rev-parse --path-format=absolute --git-dir 2>/dev/null || echo '')"
  gc="$(git -C "$DOTFILES_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo '')"
  if [ -z "$gd" ] || [ -z "$gc" ]; then
    # Older git: fall back to the shape on disk. A linked worktree's .git is a
    # FILE holding `gitdir: …`; the main worktree's is a directory.
    if [ -f "$DOTFILES_DIR/.git" ]; then gd=linked; gc=main; else gd=main; gc=main; fi
  fi
  if [ "$gd" != "$gc" ]; then
    erro "this is a linked worktree, not the main checkout"
    info "installing from here would point \$HOME at this branch"
    info "run it from:  ${gc%/.git}"
    exit 1
  fi
fi

# ── 1. Dependencies ─────────────────────────────────────────────────────────
echo "▸ Checking dependencies"
missing_bins=()
for bin in stow zsh starship; do
  command -v "$bin" >/dev/null 2>&1 || missing_bins+=("$bin")
done
if [ ${#missing_bins[@]} -gt 0 ]; then
  erro "missing: ${missing_bins[*]}"
  info "install them with:  brew bundle   (from $DOTFILES_DIR)"
  exit 1
fi
info "ok — stow, zsh and starship are present"

# oh-my-zsh is not a Homebrew formula, so `brew bundle` cannot provide it — and
# zsh/.zshrc sources it unguarded. Without it every new shell opens with an
# error. Refused here, before any plan, so the failure names its cause.
#
# The plain clone is step 1 of oh-my-zsh's own manual install. Its scripted
# installer is the wrong tool for this repo: it writes a real ~/.zshrc, which
# step 4 below then refuses as a conflict.
if [ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
  erro "missing: oh-my-zsh (~/.oh-my-zsh) — zsh/.zshrc sources it"
  info "install it with:  git clone https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh"
  info "(not the curl installer: it writes its own ~/.zshrc, which would then conflict)"
  exit 1
fi
info "ok — oh-my-zsh is present"

# Which packages this run links. bash 3.2 has no set difference; a loop it is.
INSTALL=()
for pkg in "${PACKAGES[@]}"; do
  optional=0
  for opt in "${OPTIONAL_PACKAGES[@]}"; do [ "$pkg" = "$opt" ] && optional=1; done
  if [ "$optional" -eq 1 ] && [ "$WITH_CLAUDE" -eq 0 ]; then continue; fi
  INSTALL+=("$pkg")
done

# ── 2. Repository settings ──────────────────────────────────────────────────
# Two settings this repo needs that git cannot ship: hooks are never committed,
# and an alias is config, not content.
#
# --local on both, and not as a default: a `!`-alias runs from the top of the
# ACTIVE worktree, so a global alias.wt would try to run ./tools/wt.sh in every
# unrelated repository. --local also lands in .git/config, which every linked
# worktree SHARES — set once here, `git wt` works from all of them.
echo "▸ Repository settings"
if ! git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  info "not a git checkout — skipping hooks and the wt alias"
else
  # A DIFFERENT existing value is never overwritten. Silently rewriting
  # someone's core.hooksPath is worse than not setting it: they lose hooks they
  # wrote and nothing says so. Warn, print the one-line fix, carry on.
  #
  # Checked with --local, not the effective value: a GLOBAL hooksPath should be
  # overridden here without complaint. `git config --get` exits 1 when unset and
  # this script runs `set -e`, hence `|| true` INSIDE the substitution — the
  # assignment's own status is what -e inspects.
  set_local() {   # set_local <key> <wanted> <human description>
    local key="$1" want="$2" what="$3" cur
    cur="$(git -C "$DOTFILES_DIR" config --local --get "$key" 2>/dev/null || true)"
    if [ "$cur" = "$want" ]; then
      info "$what already set"
    elif [ -n "$cur" ]; then
      erro "$key is '$cur', not '$want' — leaving it alone"
      info "to switch:  git config --local $key '$want'"
    elif [ "$DRY_RUN" -eq 1 ]; then
      info "would set $key = $want"
    else
      git -C "$DOTFILES_DIR" config --local "$key" "$want"
      info "set $key = $want"
    fi
  }
  set_local core.hooksPath .githooks "the hooks path"
  set_local alias.wt '!./tools/wt.sh' "the git wt alias"
fi

# ── 3. Agent guards ─────────────────────────────────────────────────────────
# Claude Code hooks. The SCRIPTS are versioned in .claude/hooks/ and driven by
# tests/claude-hooks.test.sh; only the POINTER to them is written here, because
# .claude/settings.local.json is gitignored — Claude Code rewrites it at
# runtime, so policy living inside it would be invisible to verify.sh and
# absent from a fresh clone. Same split as .githooks plus core.hooksPath.
#
# These constrain the AGENT, not you typing in your own terminal. That bound is
# real and is stated wherever this is described.
echo "▸ Agent guards"
if ! command -v python3 >/dev/null 2>&1; then
  info "python3 missing — skipping the Claude Code hook wiring"
elif [ "$DRY_RUN" -eq 1 ]; then
  info "would wire .claude/hooks/* into .claude/settings.local.json"
else
  python3 - "$DOTFILES_DIR" <<'PY'
import json, os, sys
root = sys.argv[1]
path = os.path.join(root, ".claude", "settings.local.json")
h = os.path.join(root, ".claude", "hooks")

want = {
    # Three questions before the call, one net after, one reporter at each end.
    "PreToolUse": [
        {"matcher": "Edit|Write|NotebookEdit",
         "hooks": [{"type": "command", "command": f"{h}/guard-live-edit.sh"}]},
        {"matcher": "Bash",
         "hooks": [{"type": "command", "command": f"{h}/guard-git.sh"},
                   {"type": "command", "command": f"{h}/guard-live-write.sh"}]},
    ],
    "PostToolUse": [
        {"matcher": "Bash|Edit|Write|NotebookEdit",
         "hooks": [{"type": "command", "command": f"{h}/guard-live-drift.sh"}]},
    ],
    "SessionStart": [{"hooks": [{"type": "command", "command": f"{h}/session-start.sh"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": f"{h}/guard-stop.sh"}]}],
}


def ours(hooks):
    """True when every command in `hooks` is one of our own scripts.

    Without this, adding a guard meant hand-editing the live settings file:
    the old code refused to touch ANY existing hooks, which correctly protects
    someone else's wiring but also froze ours at whatever the first install
    wrote. Distinguishing the two is the whole fix — ours all live under
    .claude/hooks/ in this checkout, so anything else present means hands off.
    """
    if not isinstance(hooks, dict):
        return False
    for entries in hooks.values():
        for entry in entries:
            for hook in entry.get("hooks", []):
                if not str(hook.get("command", "")).startswith(h + "/"):
                    return False
    return True

try:
    with open(path) as fh:
        data = json.load(fh)
    existed = True
except FileNotFoundError:
    data = {"$schema": "https://json.schemastore.org/claude-code-settings.json"}
    existed = False
except Exception as e:
    print(f"  could not read {path} ({e}) — leaving it alone")
    sys.exit(0)

cur = data.get("hooks")
if cur == want:
    print("  agent guards already wired")
elif cur and not ours(cur):
    # Never clobber hooks someone else put there. Say what is missing and how.
    print("  .claude/settings.local.json defines hooks that are not ours — leaving them alone")
    print("  to adopt these, merge .claude/hooks/* into that file by hand")
    sys.exit(0)
else:
    verb = "updated" if cur else "wired"
    data["hooks"] = want
    with open(path, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    print(f"  {verb} agent guards" + ("" if existed else " (created settings.local.json)"))
PY
fi

# ── 4. Conflicts ────────────────────────────────────────────────────────────
# A REAL file (not a symlink) at the destination would either be swallowed by
# stow --adopt or make stow abort. Better to detect it and say so up front.
echo "▸ Looking for conflicts"
conflicts=0
remedies=()
while IFS= read -r src; do
  dest="$HOME/${src#*/}"
  [ -e "$dest" ] || continue
  # Already ours? Stow folds trees: it may symlink a whole DIRECTORY, so the
  # file inside is not itself a symlink even though it resolves into the repo.
  # Comparing resolved paths is the only check that survives tree folding —
  # `[ -L "$dest" ]` alone reports a false conflict. Found by dogfooding.
  real_dest="$(cd "$(dirname "$dest")" 2>/dev/null && pwd -P)/$(basename "$dest")"
  real_src="$DOTFILES_DIR/$src"
  [ "$real_dest" = "$real_src" ] && continue
  if [ ! -L "$dest" ]; then
    erro "exists and is NOT a symlink: $dest"
    conflicts=$((conflicts + 1))
    remedies+=("mv ~/${src#*/} ~/${src#*/}.pre-dotfiles")
  fi
done < <(cd "$DOTFILES_DIR" && find "${INSTALL[@]}" -type f -not -name '.DS_Store')

if [ "$conflicts" -gt 0 ]; then
  erro "$conflicts conflict(s). Move or delete the files above, then run again."
  # The first install on any real machine lands here — everyone already has a
  # ~/.zshrc. So the safe remedy is printed ready to paste, one line per file,
  # and keeps a backup; tests/install-fresh.test.sh runs these exact lines.
  info "to keep them as backups, run:"
  for r in "${remedies[@]}"; do info "    $r"; done
  info "to import them into the repo instead:  stow --adopt ${INSTALL[*]}"
  info "(--adopt OVERWRITES the repo content with your \$HOME copy — check git diff afterwards)"
  exit 1
fi
info "ok — no real file would be overwritten"

# ── 5. Directories the config needs to exist ────────────────────────────────
# ssh refuses a control socket in a directory others can enter, and it will not
# create the directory itself.
if [ ! -d "$HOME/.ssh/cm" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    info "would create ~/.ssh/cm (0700)"
  else
    mkdir -p "$HOME/.ssh/cm" && chmod 700 "$HOME/.ssh/cm"
    info "created ~/.ssh/cm (0700)"
  fi
else
  chmod 700 "$HOME/.ssh/cm" 2>/dev/null || true
  info "\$HOME/.ssh/cm ok"
fi

# ── 6. Symlinks ─────────────────────────────────────────────────────────────
echo "▸ Creating symlinks"
[ "$WITH_CLAUDE" -eq 0 ] && info "skipping claude (Claude Code rules) — pass --with-claude to link it"
stow_flags=(-v -d "$DOTFILES_DIR" -t "$HOME")
[ "$DRY_RUN" -eq 1 ] && stow_flags+=(-n)
stow "${stow_flags[@]}" "${INSTALL[@]}"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "▸ Dry run — nothing was modified."
  exit 0
fi

# ── 7. Verification ──────────────────────────────────────────────────────────
echo "▸ Verifying"
zsh -n "$DOTFILES_DIR/zsh/.zshrc" && info ".zshrc syntax ok"
if starship prompt >/dev/null 2>&1; then
  info "starship renders ok"
else
  erro "starship failed to render — check ~/.config/starship.toml"
fi

echo
echo "Done. Open a NEW terminal — the current one still has the old config."
echo
echo "ONE MANUAL STEP — ~/.ssh/config is yours and is never versioned."
echo "Add this line at the TOP of it (order matters: ssh takes the FIRST value"
echo "it obtains for each parameter):"
echo
echo "    Include ~/.ssh/config.d/*.conf"
echo
echo "Then check it took effect:  ssh -G <any-host> | grep controlmaster"
