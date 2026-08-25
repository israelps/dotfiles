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

for h in lib.sh guard-live-edit.sh guard-git.sh session-start.sh guard-stop.sh; do
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
fi

# --- the guards must not depend on a field being present -------------------
# Claude Code sends what it sends; a hook that misreads an unexpected shape
# must fall through to allow, never to a malformed decision that the caller
# would have to guess about.
assert_eq "an edit with no file_path falls through to allow" allow \
          "$(decision guard-live-edit.sh '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{}}')"
assert_eq "a bash call with no command falls through to allow" allow \
          "$(decision guard-git.sh '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}')"

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
