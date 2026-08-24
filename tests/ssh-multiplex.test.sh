#!/usr/bin/env bash
# PROPERTY: SSH reuses connections, and the control socket lives somewhere safe.
#
# WHY THIS MATTERS
#   `ssh` was the largest single source of agent REWORK on the machine this
#   repo came from: 69 extra turns, 13% failure rate over 878 invocations.
#   Most of that cost is connection setup — a handshake that can fail. A reused
#   socket does not redo the handshake, so it cannot fail at the handshake.
#   Measured: 508 ms -> 63 ms per call, an 88% cut.
#
#   These assertions check CONFIGURATION, not a live host: a test that needs
#   the network is a test that fails for the wrong reason.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "▸ ssh connection multiplexing"
declare_checkout_state

FRAG="$DOTFILES_DIR/ssh/.ssh/config.d/10-multiplex.conf"
assert_rc "the multiplex fragment exists" 0 test -f "$FRAG"

for d in ControlMaster ControlPath ControlPersist; do
  if grep -qE "^\s*$d\b" "$FRAG" 2>/dev/null; then ok "$d is set"; else bad "$d is set"; fi
done

# %C, not %r@%h:%p — a Unix socket path is capped near 104 bytes and the
# readable form overflows it. Verified by reproducing `ControlPath too long`.
if grep -qE "ControlPath.*%C" "$FRAG" 2>/dev/null; then
  ok "ControlPath uses %C (short hash, avoids the ~104-byte socket limit)"
else
  bad "ControlPath uses %C" "$(grep ControlPath "$FRAG" 2>/dev/null || echo absent)"
fi

# No host of yours may appear in a fragment that ships publicly.
if grep -qiE "^\s*(HostName|User|IdentityFile|Port)\b" "$FRAG" 2>/dev/null; then
  bad "the fragment carries no host-specific data" "found a host directive"
else
  ok "the fragment carries no host-specific data"
fi

# Everything above reads the FRAGMENT — true or false in any checkout, so it
# runs everywhere. Everything below reads the MACHINE: the control directory
# and the resolved ssh config belong to whichever checkout stow was run from.
# In a linked worktree they describe the main checkout, so they are skipped.

# ssh refuses to use a control dir that others can enter.
if live_checks_apply; then
  if [ -d "$HOME/.ssh/cm" ]; then
    assert_eq "\$HOME/.ssh/cm is 0700" "700" "$(_mode "$HOME/.ssh/cm")"
  else
    bad "\$HOME/.ssh/cm exists" "run ./install.sh"
  fi
else
  skip "\$HOME/.ssh/cm is 0700" \
       "linked worktree — the control directory belongs to the main checkout"
fi

# The whole chain has to resolve — fragment + your private config.
if ! command -v ssh >/dev/null 2>&1; then
  skip "ssh -G resolves the multiplex directives (Include chain works)" "ssh not installed"
elif live_checks_apply; then
  out="$(ssh -G example.invalid 2>/dev/null | grep -ciE '^controlmaster auto|^controlpersist' || true)"
  if [ "${out:-0}" -ge 2 ]; then
    ok "ssh -G resolves the multiplex directives (Include chain works)"
  else
    bad "ssh -G resolves the multiplex directives" \
        "add the Include line to the TOP of \$HOME/.ssh/config"
  fi
else
  skip "ssh -G resolves the multiplex directives (Include chain works)" \
       "linked worktree — ssh reads \$HOME/.ssh/config.d, which points at the main checkout"
fi

summary
