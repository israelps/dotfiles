#!/usr/bin/env bash
# PROPERTY: exactly one checkout is wired into $HOME, the suite knows which one,
#           and nothing can install from anywhere else.
#
# WHY THIS MATTERS
#   The working tree IS the live config, so `git switch` here reconfigures the
#   machine — starship and ssh read their config per invocation, .zshrc lands on
#   the next shell. Branch work therefore happens in linked worktrees, and that
#   split only works if two things hold:
#
#     1. tests/checkout-state.sh can tell the three states apart. If it ever
#        answers `worktree` when it should answer `absent`, every live check in
#        every suite turns into a silent no-op — a machine where stow was never
#        run would report a clean sweep. That is the exact vacuous green this
#        repo exists to prevent, installed at the root of everything.
#     2. install.sh refuses to run from a linked worktree. Run from there it
#        would repoint $HOME at a branch. Measured while building this: the old
#        install.sh, run from a worktree, reported a bogus conflict on
#        ~/.ssh/config.d/10-multiplex.conf — the first symptom of exactly that.
#
#   The classifier is a function, and lib.sh's ERR trap sees a function's return
#   status but nothing inside a subshell. So it cannot be trusted to fail loudly
#   on its own: it has to be driven through every row of its truth table.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "▸ worktree tooling and checkout state"

command -v git >/dev/null 2>&1 || { echo "  SKIP  git not available"; exit 0; }
git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "  SKIP  not a git checkout yet"; exit 0; }

# Cleanup traps are installed at the TOP LEVEL and nowhere else. lib.sh
# documents the bug: an EXIT trap set inside a $( ) fires the instant the
# substitution ends, which once deleted ZDOT_TMP before zsh ever read it. Here
# the same mistake would leave a directory inside the LIVE repository's
# .git/worktrees, which `git worktree prune` only reaps once it has vanished
# and `git gc` only after three months.
WT_TMP=""
FIX=""
_cleanup() {
  if [ -n "$WT_TMP" ]; then
    git -C "$DOTFILES_DIR" worktree remove --force "$WT_TMP/wt" >/dev/null 2>&1 || true
    rm -rf "$WT_TMP"
    git -C "$DOTFILES_DIR" worktree prune >/dev/null 2>&1 || true
  fi
  [ -n "$FIX" ] && rm -rf "$FIX"
  return 0   # an EXIT trap returning non-zero would rewrite the suite's status
}
trap '_cleanup' EXIT

# ── 1. The truth table, against a hermetic fixture ──────────────────────────
# A fixture, not the real repo, because two of these rows CANNOT be produced
# here: this machine has no unrelated clone and no un-stowed state to offer.
# Those are precisely the rows where a wrong answer is dangerous.
FIX="$(mktemp -d)"
mkdir -p "$FIX/home" "$FIX/nohome" "$FIX/repo/zsh" "$FIX/unrelated/zsh"
: > "$FIX/repo/zsh/.zshrc"
: > "$FIX/unrelated/zsh/.zshrc"

# -c on the command line, never `git config`: a fixture must not depend on this
# machine having a committer identity, and must not write one anywhere.
_fixture_repo() {
  git -c init.defaultBranch=main init -q "$1" >/dev/null 2>&1
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" -c user.name=t -c user.email=t@t commit -qm init >/dev/null 2>&1
}
_fixture_repo "$FIX/repo"
_fixture_repo "$FIX/unrelated"
ln -s "$FIX/repo/zsh/.zshrc" "$FIX/home/.zshrc"
git -C "$FIX/repo"      worktree add --detach -q "$FIX/wt" HEAD >/dev/null 2>&1
git -C "$FIX/unrelated" worktree add --detach -q "$FIX/unrelated-wt" HEAD >/dev/null 2>&1

# Non-vacuity first. Without these, every comparison below is two `none:`
# sentinels agreeing for the wrong reason and the whole section is theatre.
assert_rc "the fixture's stow link resolves"      0 test -e "$FIX/home/.zshrc"
assert_rc "the fixture's worktree was created"    0 test -f "$FIX/wt/zsh/.zshrc"
assert_rc "the unrelated repo's worktree exists"  0 test -f "$FIX/unrelated-wt/zsh/.zshrc"

# The ( ) is what makes HOME and DOTFILES_DIR restore themselves. It also hides
# failures from the ERR trap, which is why every row asserts a VALUE and never
# an exit status.
_state_of() { ( HOME="$1"; DOTFILES_DIR="$2"; checkout_state ); }

assert_eq "the stowed checkout classifies as stowed" \
          stowed   "$(_state_of "$FIX/home"   "$FIX/repo")"
assert_eq "a linked worktree of the stowed repo classifies as worktree" \
          worktree "$(_state_of "$FIX/home"   "$FIX/wt")"
assert_eq "an unrelated clone classifies as absent, not worktree" \
          absent   "$(_state_of "$FIX/home"   "$FIX/unrelated")"
# The row that closes the hole: a linked worktree is not a free pass on its own.
# It has to be a worktree of the repo that actually configures this $HOME.
assert_eq "a linked worktree of an UNRELATED repo classifies as absent" \
          absent   "$(_state_of "$FIX/home"   "$FIX/unrelated-wt")"
assert_eq "a machine stow never touched classifies as absent" \
          absent   "$(_state_of "$FIX/nohome" "$FIX/repo")"

# ── 2. install.sh must refuse to run from a linked worktree ────────────────
WT_TMP="$(mktemp -d)"
# --detach: no branch is created, so there is nothing to leak and nothing that
# can collide with a real branch name.
if git -C "$DOTFILES_DIR" worktree add --detach "$WT_TMP/wt" HEAD >/dev/null 2>&1 \
   && [ -d "$WT_TMP/wt" ]; then
  ok "a linked worktree of this repo can be created"
else
  bad "a linked worktree of this repo can be created" "git worktree add failed — nothing below could run"
  summary; exit 1
fi

# The worktree checks out HEAD, so it carries the COMMITTED install.sh. The file
# under test is the one in the working tree, which may not be committed yet.
# Copying it in at test time cannot drift — it is the same bytes, read now.
cp "$DOTFILES_DIR/install.sh" "$WT_TMP/wt/install.sh"

out=""; rc=0
out="$("$WT_TMP/wt/install.sh" --dry-run 2>&1)" || rc=$?

# Two separate properties. "Exited non-zero" alone would also be satisfied by
# install.sh failing because stow is missing — a refusal for the wrong reason.
assert_fails "install.sh refuses to run from a linked worktree" test "$rc" -eq 0
case "$out" in
  *"linked worktree"*) ok "install.sh names the reason it refused" ;;
  *) bad "install.sh names the reason it refused" \
         "got: $(printf '%s' "$out" | head -2 | tr '\n' ' ')" ;;
esac

# It must refuse EVEN in a dry run. A dry run from the wrong directory should
# say "wrong directory", not print a plausible plan someone then trusts.
case "$out" in
  *"Creating symlinks"*) bad "the refusal happens before any plan is printed" \
                             "it got as far as the stow section" ;;
  *) ok "the refusal happens before any plan is printed" ;;
esac

# ── 3. Two things that silently disable the whole design ───────────────────
# git ignores a non-executable hook without a word — no error, no warning.
assert_rc "the post-checkout hook is executable" 0 test -x "$DOTFILES_DIR/.githooks/post-checkout"
assert_eq "core.hooksPath points at .githooks" ".githooks" \
          "$(git -C "$DOTFILES_DIR" config --get core.hooksPath 2>/dev/null || echo unset)"
assert_rc "tools/wt.sh is executable" 0 test -x "$DOTFILES_DIR/tools/wt.sh"

# ── 4. The siren must be silent in every case that is not a real switch ────
# Driven with synthetic arguments, so no branch is moved to test it. The case
# that SHOULD fire cannot be driven this way — it reads the real HEAD — and is
# covered by the end-to-end run in docs/worktree-workflow.md.
HOOK="$DOTFILES_DIR/.githooks/post-checkout"
NULLREF=0000000000000000000000000000000000000000
REALREF="$(git -C "$DOTFILES_DIR" rev-parse HEAD)"
_hook_is_silent() {   # _hook_is_silent <desc> <old> <new> <flag>
  local o
  o="$("$HOOK" "$2" "$3" "$4" 2>&1)" || true
  if [ -z "$o" ]; then ok "the siren stays silent: $1"
  else bad "the siren stays silent: $1" "it printed: $(printf '%s' "$o" | head -1)"; fi
}
_hook_is_silent "a path checkout (git restore, git checkout -- file)" "$REALREF" "$REALREF" 0
_hook_is_silent "a null old-ref (git clone, git worktree add)"        "$NULLREF" "$REALREF" 1

# ── 5. What the skip is anchored to ────────────────────────────────────────
# A skip nobody can falsify is not a skip, it is a hole. When this suite runs
# in a linked worktree the live checks are skipped everywhere — so the proof
# that earned the skip is stated here as a PASS. The day the main checkout
# stops being stowed, this is what says so.
case "$CHECKOUT_STATE" in
  stowed)
    ok "this checkout is the stowed one — the live checks ran"
    got="$( ( DOTFILES_DIR="$WT_TMP/wt"; checkout_state ) )"
    assert_eq "a real linked worktree of this repo classifies as worktree" worktree "$got" ;;
  worktree)
    ok "the live config is the main worktree's ($(main_worktree_path)), not this branch's"
    skip "a real linked worktree of this repo classifies as worktree" \
         "already proven by the fixture rows above" ;;
  *)
    bad "this checkout is stowed or a worktree of the stowed repo" \
        "state is '$CHECKOUT_STATE' — run ./install.sh from the main checkout" ;;
esac

summary
