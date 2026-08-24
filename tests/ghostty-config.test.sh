#!/usr/bin/env bash
# PROPERTY: every Ghostty setting this repo makes a claim about is the setting
#           GHOSTTY RESOLVED — never the one the file appears to say.
#
# WHY THIS MATTERS
#   Reading the file is not evidence. Measured on this machine: Ghostty does
#   not accept a trailing comment on a value line, and `background-blur = 20`
#   followed by a comment parsed the comment as part of the number — the blur
#   came out 0 while the file still read like it said 20. A grep over
#   ghostty/.config/ghostty/config would have called that green. So every
#   assertion here goes through `ghostty +show-config`, which prints what the
#   running terminal actually holds.
#
#   Two of these settings are load-bearing for an agent session:
#     * macos-option-as-alt — without it macOS sends no Meta, so every Option
#       shortcut in the Claude Code prompt (Option+Enter for a newline,
#       Option+P for the model) does nothing. The terminal-config docs name
#       this as the single thing a Ghostty user has to set by hand.
#     * notify-on-command-finish — measured: 651 Bash commands ran longer than
#       30s across 254 agent sessions, 19.5 hours of waiting. Without the
#       notification you either watch the terminal or lose the time.
#
#   NOT asserted here, deliberately: that nothing binds shift+enter. That is a
#   default of Ghostty, not a claim this repo makes — see the closing note in
#   docs/claude-code-tuning.md. Asserting it would test the vendor.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "▸ ghostty resolved configuration"

CONF="$DOTFILES_DIR/ghostty/.config/ghostty/config"

# The CLI lives inside the app bundle. Homebrew's cask puts it on $PATH, but a
# non-interactive shell may not have that; fall back to the bundle before
# skipping, so the suite does not go quiet on a machine where it could run.
if command -v ghostty >/dev/null 2>&1; then
  GHOSTTY=ghostty
elif [ -x /Applications/Ghostty.app/Contents/MacOS/ghostty ]; then
  GHOSTTY=/Applications/Ghostty.app/Contents/MacOS/ghostty
else
  echo "  SKIP  ghostty not installed"; exit 0
fi

assert_rc "the config file exists" 0 test -f "$CONF"

# --- 0. The resolved config must BE this repo's file -----------------------
# Without this, every assertion below could be describing a hand-edited
# ~/.config/ghostty/config and still report green — the suite would be
# measuring someone else's terminal. Compared by device:inode rather than by
# path text: `stat` is the BSD one on macOS and the GNU one elsewhere, and
# neither realpath(1) nor readlink -f is guaranteed to exist here.
LIVE="$HOME/.config/ghostty/config"
live_id="$(stat -L -f '%d:%i' "$LIVE" 2>/dev/null || stat -L -c '%d:%i' "$LIVE" 2>/dev/null || echo absent)"
repo_id="$(stat -L -f '%d:%i' "$CONF" 2>/dev/null || stat -L -c '%d:%i' "$CONF" 2>/dev/null || echo missing)"
if [ "$live_id" = "$repo_id" ]; then
  ok "\$HOME/.config/ghostty/config is this repo's file"
else
  bad "\$HOME/.config/ghostty/config is this repo's file" \
      "run ./install.sh — every check below would describe another config"
fi

# --- 1. The file must parse clean ------------------------------------------
# This is what catches the trailing-comment class at the source: Ghostty 1.3.1
# reports `invalid value "20 # radius"` and exits 1 rather than accepting it.
# Verified by feeding it exactly that line.
assert_rc "ghostty +validate-config accepts the file" 0 "$GHOSTTY" +validate-config --config-file="$CONF"

# --- 2. Read what Ghostty resolved -----------------------------------------
# `+show-config` prints ONLY what differs from the default; `--default` prints
# the vendor's own values. Both are needed: the first proves a setting took
# effect, the second tells a no-op restatement apart from a dropped line.
RESOLVED="$("$GHOSTTY" +show-config 2>/dev/null || true)"
DEFAULTS="$("$GHOSTTY" +show-config --default 2>/dev/null || true)"

if [ -z "$RESOLVED" ]; then
  bad "ghostty resolved a non-default config" \
      "+show-config printed nothing — Ghostty is running on pure defaults"
  summary; exit 1
fi
[ -n "$DEFAULTS" ] || { bad "ghostty +show-config --default returned output"; summary; exit 1; }

# value_of <config-text> <key> -> the resolved value, empty when absent.
# awk, not grep: it always exits 0, so a missing key cannot trip lib.sh's ERR
# trap and turn an ordinary "not set" into a suite-wide unexpected error.
value_of() { printf '%s\n' "$1" | awk -v k="$2" -F' = ' '$1==k {print $2}'; }

# --- 3. Named properties: the file has to say the right thing --------------
# Section 4 checks file -> runtime fidelity. These check the file itself: with
# `macos-option-as-alt = false` section 4 would still pass, and Option would
# still be dead.

assert_eq "macos-option-as-alt resolves true (Option+Enter, Option+P reach the prompt)" \
          "true" "$(value_of "$RESOLVED" macos-option-as-alt)"

if printf '%s\n' "$DEFAULTS" | grep -q '^notify-on-command-finish = '; then
  finish="$(value_of "$RESOLVED" notify-on-command-finish)"
  if [ -n "$finish" ] && [ "$finish" != never ]; then
    ok "notify-on-command-finish is on ($finish)"
  else
    bad "notify-on-command-finish is on" "resolved: ${finish:-never (the default)}"
  fi

  # `no-bell` is spelled out because the vendor default is `bell,no-notify`:
  # asking for `notify` alone keeps the bell as well. That is the whole reason
  # the line looks redundant, so the default is checked, not assumed — if
  # Ghostty ever changes it, this is where the comment goes stale.
  assert_eq "the vendor default is still bell,no-notify (why no-bell is spelled out)" \
            "bell,no-notify" "$(value_of "$DEFAULTS" notify-on-command-finish-action)"
  action="$(value_of "$RESOLVED" notify-on-command-finish-action)"
  case ",$action," in
    *,notify,*) case ",$action," in
                  *,no-bell,*) ok "notify-on-command-finish-action = $action (desktop notification, no bell)" ;;
                  *)           bad "notify-on-command-finish-action silences the bell" "resolved: $action" ;;
                esac ;;
    *) bad "notify-on-command-finish-action requests a notification" "resolved: ${action:-unset}" ;;
  esac

  # 30s is measured, not taste: >10s fires on 8.9% of commands (noise),
  # >30s on 4.7%, >60s on 3.0%.
  assert_eq "notify-on-command-finish-after = 30s (the measured threshold)" \
            "30s" "$(value_of "$RESOLVED" notify-on-command-finish-after)"
else
  bad "this Ghostty knows notify-on-command-finish" \
      "the key is absent from +show-config --default — needs Ghostty >= 1.3.0; the notification block in ghostty/ has no effect"
fi

# Shell integration is a dependency, not a preference: notify-on-command-finish
# has no way to know a command finished without it.
si="$(value_of "$RESOLVED" shell-integration)"
if [ "$si" = none ]; then
  bad "shell integration is enabled (notify-on-command-finish depends on it)" "resolved: none"
else
  ok "shell integration is enabled${si:+ ($si)} — notify-on-command-finish depends on it"
fi

# Requested features merge into the default list, so this key is checked
# member by member. It is the one key section 4 cannot compare literally.
feats="$(value_of "$RESOLVED" shell-integration-features)"
for f in ssh-env ssh-terminfo; do
  case ",$feats," in
    *",$f,"*) ok "shell-integration-features includes $f" ;;
    *)        bad "shell-integration-features includes $f" "resolved: ${feats:-unset}" ;;
  esac
done

# --- 4. Fidelity: every key in the file is the key Ghostty holds ------------
# The general form of the trailing-comment bug. Nothing is hand-picked here:
# the list comes from the file, so a key added later is covered without
# touching this suite.
keys=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  key="${line%% = *}"; val="${line#* = }"
  # Ghostty prints values unquoted: font-family = "JetBrains…" -> JetBrains…
  case "$val" in '"'*'"') val="${val#\"}"; val="${val%\"}" ;; esac
  [ "$key" = shell-integration-features ] && continue   # merged; asserted above
  keys=$((keys + 1))
  if printf '%s\n' "$RESOLVED" | grep -qx "$key = $val"; then
    ok "$key = $val"
  elif printf '%s\n' "$RESOLVED" | grep -q "^$key = "; then
    bad "$key = $val" "ghostty resolved: $(value_of "$RESOLVED" "$key")"
  else
    # +show-config omits anything equal to the default, so absence means the
    # line changed nothing — correct, but the line is doing no work.
    ok "$key = $val (equals Ghostty's default — the line is a no-op)"
  fi
done < <(grep -E '^[a-z][a-z0-9-]* = ' "$CONF" 2>/dev/null || true)

# A loop that read nothing would have reported a clean sweep of zero keys.
if [ "$keys" -ge 10 ]; then
  ok "checked $keys keys from the file against the resolved config"
else
  bad "the file's keys were read" "only $keys parsed — expected the whole config"
fi

summary
