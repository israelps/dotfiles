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
render_rc=0
timeout 10 env STARSHIP_CONFIG="$TOML" starship prompt >/dev/null 2>&1 || render_rc=$?
if [ "$render_rc" -eq 124 ]; then
  bad "prompt renders without hanging" "timed out"
else
  ok "prompt renders without hanging"
fi

# 4. Rendering must emit no warning. A warning means a module silently vanished.
warn="$(env STARSHIP_CONFIG="$TOML" starship prompt 2>&1 >/dev/null | grep -c 'WARN' || true)"
assert_eq "prompt emits no warning" "0" "$warn"

summary
