#!/usr/bin/env bash
# Measures a CANDIDATE checkout's shell against the live one, without
# installing either. Agent-facing: it prints a table, takes no input, and
# touches nothing under $HOME.
#
#   ./measure/compare.sh ../dotfiles-wt/fix/faster-prompt
#
# WHY THIS EXISTS
#   CLAUDE.md says "first show the measurement that justifies it". Until now
#   that rule was unenforceable: measuring a config meant installing it, so the
#   rule demanded exactly the risk the worktree workflow exists to avoid. This
#   closes that loop — a candidate can be measured while $HOME still points at
#   main.
#
# METHOD, and every part of it is load-bearing
#
#   BOTH ARMS GO THROUGH THE SAME MECHANISM. Measuring the live config by
#   running zsh-bench bare, and the candidate through ZDOTDIR, would compare
#   two configs AND two harnesses. Both arms here are driven by ZDOTDIR and
#   STARSHIP_CONFIG pointing into their own checkout, so the only difference
#   left is the thing under test.
#
#   ORDER IS A-B-A-B-A. The machine drifts while this runs — thermal state,
#   background load, whatever else you have open. Bracketing turns that drift
#   from a hidden bias into a measured quantity.
#
#   BOTH ARMS ARE REPLICATED, and this was learned the hard way. The first
#   version ran A-B-A and took the floor from |a1-a2|, the gap between two
#   baseline samples. Two samples are not a noise estimate: run against a
#   candidate byte-identical to the live config, that pair came out 1.5 ms
#   apart by luck and the tool duly reported "exit_time_ms SLOWER by 3.7 ms".
#   A signal that invents a difference between a config and itself decides
#   nothing. The floor is now the RANGE of three baselines and two candidate
#   runs, so a lucky pair cannot manufacture resolution.
#
#   THE NOISE FLOOR IS TAKEN NOW, NOT REMEMBERED. It is the resolution of this
#   run, on this machine, at this moment. A stored figure from another day is
#   the unchecked number that .claude/rules/signals.md exists to forbid.
#
#   EACH ARM GETS A PRIVATE, DISPOSABLE ZDOTDIR, AND ONE DISCARDED WARM-UP RUN.
#   Pointing ZDOTDIR straight at a checkout's zsh/ writes .zcompdump INTO that
#   checkout — tests/lib.sh documents the same trap and builds a temp dir for
#   the same reason. Worse than the litter is what it does to the numbers: the
#   first run of an arm builds the dump and later runs read it, so in A-B-A-B-A
#   the baseline is warm three times and the candidate twice. Measured on
#   2026-08-25, that confound produced first_prompt_lag_ms SLOWER by 20.9 ms
#   and first_command_lag_ms FASTER by 49.4 ms in the SAME run, for a change
#   that only ever adds work. A warm-up run per arm, thrown away, removes it.
#
#   A DELTA INSIDE THE FLOOR IS NOT A NUMBER. It prints as "not resolvable",
#   never as a figure with a sign. Measured on 2026-08-25 at -i 3, the floor
#   was 8.2 ms against a 248 ms baseline, and an injected `sleep 0.4` showed up
#   as 440 ms. This tool sees hundreds of milliseconds and is blind below ten;
#   reporting "+3 ms faster" would be inventing precision it does not have.
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ITERS=3

info() { printf '  %s\n' "$*"; }
erro() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
usage: ./measure/compare.sh <candidate-checkout> [-i <iters>]

  Measures the candidate's shell config against the live one and prints the
  delta together with the noise floor of the same run. Installs nothing.

  <candidate-checkout>   a worktree or clone, e.g. ../dotfiles-wt/fix/x
  -i, --iters <n>        zsh-bench iterations per run (default 3)
EOF
}

CAND=""
while [ $# -gt 0 ]; do
  case "$1" in
    -i|--iters) ITERS="${2:-}"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         erro "unknown option: $1"; usage; exit 2 ;;
    *)          CAND="$1"; shift ;;
  esac
done
[ -n "$CAND" ] || { usage; exit 2; }

# The live config is whatever the MAIN worktree holds — resolved from git, not
# from $PWD, so this behaves the same run from a worktree as from main.
COMMON="$(git -C "$DOTFILES_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo '')"
MAIN="${COMMON%/.git}"
[ -n "$MAIN" ] || MAIN="$DOTFILES_DIR"

CAND="$(cd "$CAND" 2>/dev/null && pwd)" || { erro "no such directory: $CAND"; exit 1; }

BENCH="$DOTFILES_DIR/.instruments/zsh-bench/zsh-bench"
[ -x "$BENCH" ] || { erro "zsh-bench is not installed"; info "run: ./measure/bootstrap.sh"; exit 1; }

for d in "$MAIN" "$CAND"; do
  [ -f "$d/zsh/.zshrc" ] || { erro "not a dotfiles checkout: $d/zsh/.zshrc is missing"; exit 1; }
done
if [ "$CAND" = "$MAIN" ]; then
  erro "the candidate is the main checkout — there is nothing to compare"
  info "make one with:  git wt new <branch>"
  exit 1
fi

# One temp ZDOTDIR per arm, holding a symlink to that checkout's .zshrc. Created
# once and reused across that arm's runs so every measured run is equally warm;
# removed on exit so no checkout is littered.
TMPROOT="$(mktemp -d)"
cleanup() { rm -rf "$TMPROOT"; return 0; }
trap 'cleanup' EXIT

arm_zdotdir() {  # arm_zdotdir <checkout> <label> -> path to that arm's ZDOTDIR
  local d="$TMPROOT/$2"
  [ -d "$d" ] || { mkdir -p "$d"; ln -sf "$1/zsh/.zshrc" "$d/.zshrc"; }
  printf '%s\n' "$d"
}

bench_arm() {  # bench_arm <checkout> <label> -> zsh-bench's key=value block
  ZDOTDIR="$(arm_zdotdir "$1" "$2")" \
  STARSHIP_CONFIG="$1/starship/.config/starship.toml" \
    "$BENCH" -i "$ITERS" 2>/dev/null
}

metric() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

echo "▸ Comparing"
info "live       $MAIN"
info "candidate  $CAND"
info "zsh-bench -i $ITERS, order A-B-A-B-A (both arms replicated)"
echo

# Discarded. Its only job is to build each arm's compdump, so that no measured
# run below is the one paying for it.
info "warming both arms (discarded) …"
bench_arm "$MAIN" live >/dev/null; bench_arm "$CAND" cand >/dev/null

info "baseline 1/3 …";  A1="$(bench_arm "$MAIN" live)"
info "candidate 1/2 …"; B1="$(bench_arm "$CAND" cand)"
info "baseline 2/3 …";  A2="$(bench_arm "$MAIN" live)"
info "candidate 2/2 …"; B2="$(bench_arm "$CAND" cand)"
info "baseline 3/3 …";  A3="$(bench_arm "$MAIN" live)"
echo

for blk in "$A1" "$B1" "$A2" "$B2" "$A3"; do
  [ -n "$blk" ] || { erro "a benchmark run produced nothing — is zsh your login shell?"; exit 1; }
done

printf '  %-24s %10s %10s %10s %s\n' METRIC LIVE CANDIDATE DELTA VERDICT
printf '  %-24s %10s %10s %10s %s\n' "------" "----" "---------" "-----" "-------"

resolvable=0
for m in first_prompt_lag_ms first_command_lag_ms command_lag_ms input_lag_ms exit_time_ms; do
  a1="$(metric "$A1" "$m")"; a2="$(metric "$A2" "$m")"; a3="$(metric "$A3" "$m")"
  b1="$(metric "$B1" "$m")"; b2="$(metric "$B2" "$m")"
  [ -n "$a1" ] && [ -n "$a2" ] && [ -n "$a3" ] && [ -n "$b1" ] && [ -n "$b2" ] || continue
  # awk, not bc: bc is not guaranteed and awk is already used by the suites.
  # The floor is the WIDER of the two arms' ranges — the worst spread either
  # config showed while nothing about it was changing.
  stats="$(awk -v a1="$a1" -v a2="$a2" -v a3="$a3" -v b1="$b1" -v b2="$b2" 'BEGIN{
      amin=a1; amax=a1;
      if(a2<amin)amin=a2; if(a2>amax)amax=a2;
      if(a3<amin)amin=a3; if(a3>amax)amax=a3;
      bmin=(b1<b2?b1:b2); bmax=(b1>b2?b1:b2);
      base=(a1+a2+a3)/3; cand=(b1+b2)/2;
      na=amax-amin; nb=bmax-bmin; noise=(na>nb?na:nb);
      d=cand-base; ad=(d<0?-d:d);
      printf "%.4f %.4f %.4f %.4f %d", base, cand, d, noise, (ad>noise?1:0) }')"
  set -- $stats
  base="$1"; cand="$2"; d="$3"; noise="$4"; res="$5"
  if [ "$res" -eq 1 ]; then
    verdict="$(awk -v d="$d" -v n="$noise" 'BEGIN{ ad=(d<0?-d:d);
        printf "%s by %.1f ms, floor %.1f", (d<0?"FASTER":"SLOWER"), ad, n }')"
    resolvable=$((resolvable + 1))
  else
    verdict="$(awk -v n="$noise" 'BEGIN{ printf "not resolvable (noise %.1f ms)", n }')"
  fi
  awk -v m="$m" -v base="$base" -v cand="$cand" -v d="$d" -v v="$verdict" 'BEGIN{
      printf "  %-24s %10.1f %10.1f %+10.1f %s\n", m, base, cand, d, v }'
done

echo
if [ "$resolvable" -eq 0 ]; then
  info "nothing moved beyond this run's noise floor."
  info "that is a result, not a failure: the change costs nothing measurable here."
else
  info "$resolvable metric(s) moved beyond the noise floor of this run."
fi

# A number cannot see a prompt going ugly. Rendering both is cheap and needs no
# interactive shell — the one thing that would otherwise need your eyes.
echo
info "prompt, rendered from each config (no shell opened):"
for pair in "live:$MAIN" "candidate:$CAND"; do
  label="${pair%%:*}"; dir="${pair#*:}"
  printf '    %-10s ' "$label"
  STARSHIP_CONFIG="$dir/starship/.config/starship.toml" starship prompt --status=0 2>/dev/null \
    | tr -d '\n' | sed 's/%{//g; s/%}//g'
  printf '\n'
done
