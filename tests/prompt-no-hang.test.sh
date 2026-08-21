#!/usr/bin/env bash
# PROPERTY: the prompt cannot hang, and cannot silently drop a segment.
#
# WHY THIS MATTERS
#   A prompt is drawn after EVERY command, including every command an agent
#   runs. Any subprocess it spawns is on that hot path.
#   Measured on this machine: Starship's native [golang] module runs
#   `go version` per prompt. In a directory whose go.mod requires an absent
#   toolchain, GOTOOLCHAIN=auto makes go try to DOWNLOAD it — 1553 ms, versus
#   7 ms normally. That is where "Executing command ... timed out" came from.
#   The rule this suite enforces: any command the prompt runs must be bounded
#   BY CONSTRUCTION, not by a timeout that hopes for the best.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "▸ the prompt cannot hang"

TOML="$DOTFILES_DIR/starship/.config/starship.toml"
command -v starship >/dev/null 2>&1 || { echo "  SKIP  starship not installed"; exit 0; }

# 1. No native language module may be enabled: each one shells out per prompt.
enabled_native=0
for m in golang nodejs rust python java ruby php dotnet; do
  if grep -qE "^\[$m\]" "$TOML" 2>/dev/null && ! grep -A3 -E "^\[$m\]" "$TOML" | grep -q "disabled = true"; then
    bad "native [$m] module is off (it would spawn a subprocess per prompt)"
    enabled_native=1
  fi
done
[ "$enabled_native" -eq 0 ] && ok "no native language module is enabled"

# 2. Every command the prompt runs must be bounded by construction.
#    Today the only one is the Go version check, and it is bounded because
#    GOTOOLCHAIN=local can never reach the network.
# NOTE: no `mapfile` here on purpose — macOS ships bash 3.2, which lacks it.
# Everything in tests/ must run on the bash that comes with the OS.
cmd_count="$(grep -cE '^command = ' "$TOML" 2>/dev/null || echo 0)"
if [ "$cmd_count" -eq 0 ]; then
  ok "prompt runs no external command at all"
else
  if grep -q "GOTOOLCHAIN=local" "$DOTFILES_DIR/starship/.config/starship-go-mismatch.sh" 2>/dev/null; then
    ok "prompt command is bounded by construction (GOTOOLCHAIN=local)"
  else
      bad "prompt command is bounded by construction" "no GOTOOLCHAIN=local found"
  fi
fi

# 3. Render must be fast, and must not hang. 124 = timeout had to kill it.
#    The guard on `timeout` itself is not paranoia. macOS ships no timeout(1) —
#    it comes from coreutils, which this repo did not declare until now. With it
#    absent the run returns 127, which is not 124, so the old `else` branch
#    reported PASS while nothing had been rendered. Measured by hiding `timeout`
#    from $PATH and watching this line go green. Any non-zero rc now fails: a
#    prompt that exits 1 has not rendered, whatever the reason.
if ! command -v timeout >/dev/null 2>&1; then
  bad "prompt renders without hanging" \
      "timeout(1) is missing (brew install coreutils) — this check cannot run, and must not pretend it did"
else
  render_rc=0
  timeout 10 env STARSHIP_CONFIG="$TOML" starship prompt >/dev/null 2>&1 || render_rc=$?
  case "$render_rc" in
    0)   ok "prompt renders without hanging" ;;
    124) bad "prompt renders without hanging" "timed out after 10s" ;;
    *)   bad "prompt renders without hanging" "starship exited rc=$render_rc" ;;
  esac
fi

# 4. Rendering must emit no warning. A warning means a module silently vanished.
warn="$(env STARSHIP_CONFIG="$TOML" starship prompt 2>&1 >/dev/null | grep -c 'WARN' || true)"
assert_eq "prompt emits no warning" "0" "$warn"

summary
