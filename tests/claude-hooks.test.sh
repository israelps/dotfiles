#!/usr/bin/env bash
# PROPERTY: the agent cannot put this machine into a bad state by accident, and
#           the guards that ensure it are still working.
#
# WHY THIS MATTERS
#   Every other mechanism in this repo watches GIT. install.sh refuses to run
#   from a worktree, .githooks/post-checkout warns when the checkout leaves
#   main, the suites skip live checks in a worktree. On 2026-08-25 an entire
#   day's work went onto the live tree anyway, and not one of them fired —
#   because the change arrived as an EDIT. ~/.zshrc is a symlink into this
#   checkout, so a save is live before any git command exists to be watched.
#
#   .claude/hooks/ closes that. These are Claude Code hooks, so they constrain
#   the AGENT and not the owner typing in their own terminal — a bounded claim,
#   and the bound is stated here so nobody reads it as more.
#
#   A guard nobody drives is a guard that quietly stops working, and it stops
#   working in exactly the silent way this repo exists to prevent: no error, no
#   red, just a hook that allows everything. So each one is driven here with
#   the JSON Claude Code actually sends it.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "▸ the agent-facing guards"
declare_checkout_state

HOOKS="$DOTFILES_DIR/.claude/hooks"
command -v jq >/dev/null 2>&1 || { echo "  SKIP  jq not available — the hooks need it to parse their input"; exit 0; }

for h in lib.sh guard-live-edit.sh guard-live-write.sh guard-live-drift.sh \
         guard-git.sh session-start.sh guard-stop.sh; do
  assert_rc "$h is executable" 0 test -x "$HOOKS/$h"
done

# decision <script> <json> -> "deny" | "allow"
# A hook that denies prints a permissionDecision on stdout; one that allows
# prints nothing at all. Anything else is neither, and the caller must not
# quietly read it as "allow".
decision() {
  local out
  out="$(printf '%s' "$2" | "$HOOKS/$1" 2>/dev/null)"
  if printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
    printf 'deny\n'
  elif [ -z "$out" ]; then
    printf 'allow\n'
  else
    printf 'malformed\n'
  fi
}

edit_json() { printf '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }
bash_json() { printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }

# The write cases carry quotes, and whether an operator sits INSIDE quotes is
# exactly what guard-live-write.sh decides on — so the escaping goes to a real
# JSON writer rather than printf's %s, which would corrupt the very signal.
bash_json_q() { python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"; }

# post_decision <script> <json> -> "block" | "allow" | "malformed"
# A PostToolUse hook cannot emit a permissionDecision: the call already ran, so
# the documented shape is {"decision":"block","reason":...}. Reading it with
# decision() would score every block as "malformed".
post_decision() {
  local out
  out="$(printf '%s' "$2" | "$1" 2>/dev/null)"
  if printf '%s' "$out" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    printf 'block\n'
  elif [ -z "$out" ]; then
    printf 'allow\n'
  else
    printf 'malformed\n'
  fi
}

# The guards are state-dependent BY DESIGN: in a linked worktree nothing under
# $HOME points here, so editing and switching are the whole point and every
# call must pass. Both directions are asserted, because "it allowed everything"
# is the correct answer in one state and total failure in the other.
if [ "$CHECKOUT_STATE" = stowed ]; then
  # --- edits that must be refused: inside a stow package ------------------
  for p in zsh/.zshrc \
           starship/.config/starship.toml \
           ghostty/.config/ghostty/config \
           ssh/.ssh/config.d/10-multiplex.conf \
           "$DOTFILES_DIR/zsh/.zshrc"; do
    assert_eq "editing $p is refused on the live checkout" deny "$(decision guard-live-edit.sh "$(edit_json "$p")")"
  done

  # --- edits that must pass: everything that is not live config -----------
  for p in tests/lib.sh README.md CLAUDE.md docs/worktree-workflow.md \
           measure/compare.sh .claude/rules/shell.md /tmp/somewhere-else.txt; do
    assert_eq "editing $p is allowed" allow "$(decision guard-live-edit.sh "$(edit_json "$p")")"
  done

  # --- shell writes into a package: the OTHER door into the live tree ------
  # guard-live-edit.sh reads .tool_input.file_path, which only the Edit tools
  # send. These arrive as Bash and reached NOTHING until guard-live-write.sh.
  # Auto mode makes this the likely shape rather than an exotic one: it tells
  # the agent to prefer sed/heredocs over the Edit tool (read from a session's
  # own context, 2026-08-25).
  for c in "sed -i '' 's/a/b/' zsh/.zshrc" \
           "sed -i.bak -e s/a/b/ starship/.config/starship.toml" \
           "echo x > zsh/.zshrc" \
           "echo x >> zsh/.zshrc" \
           "echo x >zsh/.zshrc" \
           "printf x | tee ssh/.ssh/config.d/10-multiplex.conf" \
           "cp /tmp/new zsh/.zshrc" \
           "mv /tmp/new zsh/.zshrc" \
           "rm zsh/.zshrc" \
           "dd if=/dev/null of=zsh/.zshrc" \
           "git status && echo x > zsh/.zshrc" \
           "echo x > ghostty/.config/ghostty/config" \
           "sed -i '' s/a/b/ $DOTFILES_DIR/zsh/.zshrc" \
           "sed -i '' s/a/b/ ~/.zshrc" \
           'echo x > "zsh/.zshrc"'; do
    assert_eq "'$c' is refused on the live checkout" deny \
              "$(decision guard-live-write.sh "$(bash_json_q "$c")")"
  done

  # Two of those carry the whole point. `~/.zshrc` is a SYMLINK into this
  # checkout, so a path check alone would call it foreign; package_of() follows
  # it. And `> "zsh/.zshrc"` is a fully-quoted target, which a naive strip of
  # quoted text would have missed entirely.

  # --- shell commands that must NOT be refused -----------------------------
  # A guard that blocks ordinary work is a guard the owner turns off, and then
  # there is no guard at all. Reading a package, writing anywhere else, and
  # writing into a worktree all have to pass — that last one is the workflow
  # this guard exists to push people toward.
  #
  # The last row is a false positive this guard actually shipped with, caught
  # by it refusing the commit that was adding these very tests: a write pattern
  # inside quotes is a SENTENCE about a write, not a write.
  for c in "cat zsh/.zshrc" \
           "grep -n x zsh/.zshrc > /tmp/out.txt" \
           "cat zsh/.zshrc | tee /tmp/copy.txt" \
           "cp zsh/.zshrc /tmp/backup" \
           "sed -n '1,20p' zsh/.zshrc" \
           "sed -i '' s/a/b/ ../dotfiles-wt/feat/zsh/.zshrc" \
           "sed -i '' s/a/b/ tests/lib.sh" \
           "sed -i '' s/a/b/ .claude/rules/shell.md" \
           "echo x > README.md" \
           "echo x > /tmp/scratch" \
           "rm /tmp/junk" \
           "git diff zsh/.zshrc" \
           "./verify.sh" \
           'echo "to write it: echo x > zsh/.zshrc"'; do
    assert_eq "'$c' is allowed" allow \
              "$(decision guard-live-write.sh "$(bash_json_q "$c")")"
  done

  # A heredoc BODY is stdin data, not commands — the other false positive this
  # guard shipped with. Asserted separately because it needs a real newline,
  # which the single-line loops cannot carry.
  assert_eq "a heredoc body that merely mentions a package write is allowed" allow \
            "$(decision guard-live-write.sh "$(bash_json_q 'cat > tests/lib.sh <<EOF
echo x > zsh/.zshrc
EOF')")"
  assert_eq "a heredoc writing INTO a package is still refused" deny \
            "$(decision guard-live-write.sh "$(bash_json_q 'cat > zsh/.zshrc <<EOF
export FOO=1
EOF')")"

  # --- git that replaces the working tree ---------------------------------
  for c in "git switch feature/x" "git checkout -b feature/x" "git stash push -m wip" \
           "git reset --hard HEAD~1"; do
    assert_eq "'$c' is refused on the live checkout" deny "$(decision guard-git.sh "$(bash_json "$c")")"
  done

  # --- git that must never be refused -------------------------------------
  # `git switch main` is the CURE. Refusing it would leave someone stranded on
  # a branch with the tool that fixes it blocked.
  for c in "git switch main" "git status --porcelain" "git log --oneline -5" \
           "git checkout -- zsh/.zshrc" "git wt new feature/x" "git wt list"; do
    assert_eq "'$c' is allowed" allow "$(decision guard-git.sh "$(bash_json "$c")")"
  done
else
  # In a worktree the guards must get out of the way completely.
  assert_eq "editing a package is allowed in a worktree" allow \
            "$(decision guard-live-edit.sh "$(edit_json zsh/.zshrc)")"
  assert_eq "switching branches is allowed in a worktree" allow \
            "$(decision guard-git.sh "$(bash_json 'git switch feature/x')")"
  assert_eq "a shell write into a package is allowed in a worktree" allow \
            "$(decision guard-live-write.sh "$(bash_json_q 'echo x > zsh/.zshrc')")"
  assert_eq "drift is not reported in a worktree" allow \
            "$(post_decision "$HOOKS/guard-live-drift.sh" '{"session_id":"wt"}')"
fi

# --- the net: did the live surface move, however it moved -------------------
# Driven against a HERMETIC FIXTURE, not this repo, and the reason is the same
# one worktree.test.sh gives: the interesting rows cannot be produced here.
# Producing real drift in this checkout means writing to the live config, which
# is the exact act under test — a suite that had to break the invariant to
# check the invariant would be worse than no suite.
#
# The fixture is a whole small dotfiles: its own install.sh (so stow_packages
# has something to read), its own copy of the hooks (so DOTFILES_DIR resolves
# to the fixture), its own $HOME with the stow symlink (so checkout_state says
# "stowed"), and its own TMPDIR (so baselines cannot collide with the real
# session's).
DFIX=""
_drift_cleanup() { [ -n "$DFIX" ] && rm -rf "$DFIX"; return 0; }
trap '_drift_cleanup' EXIT

DFIX="$(mktemp -d)"
mkdir -p "$DFIX/repo/zsh" "$DFIX/repo/.claude" "$DFIX/repo/tests" "$DFIX/home" "$DFIX/tmp"
cp -R "$HOOKS" "$DFIX/repo/.claude/hooks"
cp "$DOTFILES_DIR/tests/checkout-state.sh" "$DFIX/repo/tests/"
printf 'PACKAGES=(zsh)\n'  > "$DFIX/repo/install.sh"
printf 'export A=1\n'      > "$DFIX/repo/zsh/.zshrc"
printf '# readme\n'        > "$DFIX/repo/README.md"
git -c init.defaultBranch=main init -q "$DFIX/repo" >/dev/null 2>&1
git -C "$DFIX/repo" add -A >/dev/null 2>&1
git -C "$DFIX/repo" -c user.name=t -c user.email=t@t commit -qm init >/dev/null 2>&1
ln -s "$DFIX/repo/zsh/.zshrc" "$DFIX/home/.zshrc"

# _fx <script> [json] -> run a fixture hook with the fixture's HOME and TMPDIR.
# `env -` is deliberate: inheriting this suite's DOTFILES_DIR would point the
# hook back at the real repo and the fixture would be theatre.
_fx() {
  env - PATH="$PATH" HOME="$DFIX/home" TMPDIR="$DFIX/tmp" \
      sh -c "printf '%s' '$2' | '$DFIX/repo/.claude/hooks/$1'" 2>/dev/null
}
# Same call, stderr instead of stdout. Separate because _fx discards stderr on
# purpose (a hook's diagnostics would otherwise litter the suite's output), and
# fail_open's whole contract is a message on stderr — so testing it needs the
# stream _fx throws away.
_fx_err() {
  env - PATH="$PATH" HOME="$DFIX/home" TMPDIR="$DFIX/tmp" \
      sh -c "printf '%s' '$2' | '$DFIX/repo/.claude/hooks/$1'" 2>&1 >/dev/null
}
_fx_drift_raw() {
  local out
  out="$(_fx guard-live-drift.sh "$1")"
  if printf '%s' "$out" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then printf 'block\n'
  elif [ -z "$out" ]; then printf 'allow\n'
  else printf 'malformed\n'; fi
}
_fx_drift() {
  local out
  out="$(_fx guard-live-drift.sh "{\"session_id\":\"$1\"}")"
  if printf '%s' "$out" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then printf 'block\n'
  elif [ -z "$out" ]; then printf 'allow\n'
  else printf 'malformed\n'; fi
}

# Non-vacuity first. Every row below is meaningless if the fixture does not
# classify as stowed — the hooks would allow everything for the wrong reason.
assert_eq "the fixture classifies as the stowed checkout" \
          "dotfiles: stowed checkout on main" \
          "$(_fx session-start.sh '{"session_id":"probe"}' | head -1)"

# 1. A clean session drifts nowhere.
_fx session-start.sh '{"session_id":"s1"}' >/dev/null
assert_rc "SessionStart recorded a drift baseline" 0 test -f "$DFIX/tmp/dotfiles-drift-s1"
assert_eq "no change means no drift reported" allow "$(_fx_drift s1)"

# 2. A change inside a package is reported, no matter how it got there. This is
#    written with plain shell on purpose: it stands in for every door the
#    PreToolUse guards cannot see (python3 -c, perl -i, a path from a variable).
printf 'export A=2\n' > "$DFIX/repo/zsh/.zshrc"
assert_eq "a package file changed during the session is reported" block "$(_fx_drift s1)"

# 3. And reported ONCE. A PostToolUse hook that keeps blocking is a trap with
#    no exit, firing on every later tool call.
assert_eq "the same drift is not reported twice" allow "$(_fx_drift s1)"

# 4. Changes outside the packages are not this hook's business.
printf '# touched\n' >> "$DFIX/repo/README.md"
assert_eq "a change outside every package is not drift" allow "$(_fx_drift s1)"

# 5. THE PROPERTY THAT KEEPS THIS GUARD TRUSTED: the owner's own uncommitted
#    work must never read as the agent's doing. zsh/.zshrc is still dirty from
#    step 2; a fresh session starts from that as its floor and says nothing.
_fx session-start.sh '{"session_id":"s2"}' >/dev/null
assert_eq "pre-existing dirt is the floor of a new session, not its drift" \
          allow "$(_fx_drift s2)"

# 6. ...and the new session still catches what IT moves.
printf 'export B=1\n' > "$DFIX/repo/zsh/.zprofile"
assert_eq "the new session still reports its own drift" block "$(_fx_drift s2)"

# 7. No session id means the hook CANNOT tell whose changes these are. It must
#    fail open rather than fall back to a shared baseline file: two sessions on
#    one floor is the cross-session contamination this mechanism exists to
#    prevent. Found by a stray dotfiles-drift-unknown in TMPDIR, 2026-08-25.
# Both rows below have to DISCRIMINATE. Asserting only "it allowed" would pass
# whether the hook fails open or silently adopts a shared floor — both return
# allow. What differs is the stated reason and the absence of a file, so those
# are what get asserted. (Caught by mutation: restoring the shared fallback left
# an allow-only row green.)
_fx_drift_err() { _fx_err guard-live-drift.sh "$1"; }
case "$(_fx_drift_err '{}')" in
  *session_id*) ok "a payload with no session_id fails open and names the reason" ;;
  *) bad "a payload with no session_id fails open and names the reason" \
         "stderr said: $(_fx_drift_err '{}')" ;;
esac
assert_rc "...and writes no shared 'unknown' baseline" 1 \
          test -e "$DFIX/tmp/dotfiles-drift-unknown"

# 8. A missing baseline must adopt a floor, never read the whole surface as
#    drift. Otherwise a cleared TMPDIR turns into a false accusation.
rm -f "$DFIX/tmp/dotfiles-drift-s3"
assert_eq "a session with no baseline adopts a floor instead of accusing" \
          allow "$(_fx_drift s3)"
assert_rc "...and writes the baseline it adopted" 0 test -f "$DFIX/tmp/dotfiles-drift-s3"

# --- the guards must not depend on a field being present -------------------
# Claude Code sends what it sends; a hook that misreads an unexpected shape
# must fall through to allow, never to a malformed decision that the caller
# would have to guess about.
assert_eq "an edit with no file_path falls through to allow" allow \
          "$(decision guard-live-edit.sh '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{}}')"
assert_eq "a bash call with no command falls through to allow" allow \
          "$(decision guard-git.sh '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}')"
assert_eq "the write guard with no command falls through to allow" allow \
          "$(decision guard-live-write.sh '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}')"

# --- SessionStart reports, and cannot block --------------------------------
out="$(printf '{"hook_event_name":"SessionStart"}' | "$HOOKS/session-start.sh" 2>/dev/null)"; rc=$?
assert_eq "SessionStart exits 0 (it must never block a session)" 0 "$rc"
case "$out" in
  *"$CHECKOUT_STATE"*) ok "SessionStart names the checkout state ($CHECKOUT_STATE)" ;;
  *) bad "SessionStart names the checkout state" "printed: ${out:-<nothing>}" ;;
esac

# --- Stop lets the turn end when the checkout is where it belongs ----------
if [ "$CHECKOUT_STATE" = stowed ] \
   && [ "$(git -C "$DOTFILES_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null)" = main ]; then
  assert_rc "Stop allows the turn to end while the checkout is on main" 0 \
            env - PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
            sh -c "printf '{\"session_id\":\"t\"}' | '$HOOKS/guard-stop.sh'"
else
  skip "Stop allows the turn to end while the checkout is on main" \
       "only meaningful on the stowed checkout while it is on main"
fi

# --- the wiring, which is local and therefore easy to lose -----------------
# The scripts are versioned; the pointer to them is not, because Claude Code
# rewrites settings.json at runtime. install.sh writes it, and this is what
# notices when it is gone.
SETTINGS="$DOTFILES_DIR/.claude/settings.local.json"
if [ -f "$SETTINGS" ]; then
  wired="$(python3 -c "
import json,sys
try: d=json.load(open('$SETTINGS'))
except Exception: print('unreadable'); sys.exit()
h=d.get('hooks',{})
print(','.join(sorted(h.keys())) or 'none')" 2>/dev/null)"
  case "$wired" in
    *PreToolUse*) ok "the hooks are wired into settings.local.json ($wired)" ;;
    *) bad "the hooks are wired into settings.local.json" \
           "found: ${wired:-none} — run ./install.sh" ;;
  esac
else
  bad "the hooks are wired into settings.local.json" "$SETTINGS does not exist — run ./install.sh"
fi

summary
