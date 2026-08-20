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

# ssh refuses to use a control dir that others can enter.
if [ -d "$HOME/.ssh/cm" ]; then
  perm="$(stat -f '%Lp' "$HOME/.ssh/cm" 2>/dev/null || stat -c '%a' "$HOME/.ssh/cm" 2>/dev/null)"
  assert_eq "\$HOME/.ssh/cm is 0700" "700" "$perm"
else
  bad "\$HOME/.ssh/cm exists" "run ./install.sh"
fi

# The whole chain has to resolve — fragment + your private config.
if command -v ssh >/dev/null 2>&1; then
  out="$(ssh -G example.invalid 2>/dev/null | grep -ciE '^controlmaster auto|^controlpersist' || true)"
  if [ "${out:-0}" -ge 2 ]; then
    ok "ssh -G resolves the multiplex directives (Include chain works)"
  else
    bad "ssh -G resolves the multiplex directives" \
        "add the Include line to the TOP of \$HOME/.ssh/config"
  fi
fi

summary
