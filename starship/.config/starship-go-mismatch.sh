# Warns when the installed Go does not satisfy what this worktree requires.
# Silent when everything matches — the warning is the only output.
#
# GOTOOLCHAIN=local is the whole point: it can never reach the network, so this
# script is bounded BY CONSTRUCTION rather than by a timeout that hopes.
# Starship's native [golang] module is not: with GOTOOLCHAIN=auto, `go version`
# in a directory requiring an absent toolchain tries to DOWNLOAD it — measured
# at 1553 ms against 7 ms normally, on a path that runs after every command.

# Required: the first "go X.Y[.Z]" from go.work (which wins) or go.mod
req=$(awk '/^go [0-9]/{print $2; exit}' go.work 2>/dev/null)
[ -z "$req" ] && req=$(awk '/^go [0-9]/{print $2; exit}' go.mod 2>/dev/null)
[ -z "$req" ] && exit 0

installed=$(GOTOOLCHAIN=local go env GOVERSION 2>/dev/null | sed 's/^go//')
[ -z "$installed" ] && exit 0

# `sort -V` picks the lower of the two. If the lower one is not the required
# version, the installed toolchain is behind.
if [ "$(printf '%s\n%s\n' "$req" "$installed" | sort -V | head -1)" != "$req" ]; then
  printf '⚠ go%s < requires %s' "$installed" "$req"
fi
