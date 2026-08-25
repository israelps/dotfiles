#!/usr/bin/env bash
# PreToolUse on Bash. Refuses a SHELL WRITE into a stow package on the stowed
# checkout — the same refusal guard-live-edit.sh makes, through the other door.
#
# WHY A SECOND SCRIPT AND NOT A LINE IN THE FIRST
#   guard-live-edit.sh reads .tool_input.file_path, a field only
#   Edit|Write|NotebookEdit send. A Bash call carries .tool_input.command
#   instead, so `sed -i s/x/y/ zsh/.zshrc` never reached that guard at all: the
#   identical live overwrite it exists to stop, arriving as a different tool.
#
#   The door is not hypothetical. Claude Code's auto mode tells the agent to
#   "make file changes with sed, heredocs, or short scripts, rather than using
#   the dedicated Read, Edit, or Write tools" — read out of this session's own
#   context on 2026-08-25. Auto mode routes edits to precisely the tool that
#   was unwatched, and the owner reports being in auto mode ~98% of the time.
#
# WHY IT LEXES INSTEAD OF PATTERN-MATCHING
#   A substring search cannot tell a write from a SENTENCE ABOUT a write. Both
#   false positives were found by this guard refusing the very commits that
#   were adding its own tests, on 2026-08-25: once on a heredoc body holding
#   test fixtures, once on `"echo x > zsh/.zshrc"` as a quoted list element.
#   A guard that blocks ordinary work is a guard the owner turns off, and then
#   there is no guard at all — so the rule is shell semantics, not text:
#     - a heredoc BODY is stdin data, never commands (the line carrying the
#       `<<DELIM` is kept, so `cat > zsh/.zshrc <<EOF` is still caught)
#     - `>` `>>` `|` `;` are operators only OUTSIDE quotes
#     - a fully-quoted word is still a word, so `> "zsh/.zshrc"` still counts
#
# WHAT IT CANNOT SEE — say it here, because nothing on disk will
#   Targets are read out of the command TEXT. Invisible to it: an in-place edit
#   behind an interpreter (`python3 -c`, `perl -i`), a path built at runtime
#   from a variable, a path inside a script invoked by name, and an editor run
#   interactively. This narrows the door. It does not close it, and no test can
#   assert that it did. tests/claude-hooks.test.sh pins what IS covered.
# shellcheck source=.claude/hooks/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# In a linked worktree nothing under $HOME points here — writing is the point.
[ "$(checkout_state)" = stowed ] || allow

cmd="$(hook_field '.tool_input.command')"
[ -n "$cmd" ] || allow

# There is deliberately no `*dotfiles-wt*) allow` shortcut like guard-git.sh's.
# Here the TARGET is resolved, and a path under ../dotfiles-wt/ falls outside
# DOTFILES_DIR on its own — precision beats a substring that a stray mention
# in a comment could switch off.

# One token per line: "W<word>" for a word, "O<op>" for an unquoted operator.
tokens="$(printf '%s\n' "$cmd" | awk '
  # ---- pass 1: drop heredoc bodies, keep the line that opens them ----------
  {
    if (skip) {
      t = $0; gsub(/^[ \t]+|[ \t]+$/, "", t)
      if (t == delim) skip = 0
      next
    }
    buf = buf $0 "\n"
    line = $0
    while (match(line, /<<-?[ \t]*("[^"]*"|'"'"'[^'"'"']*'"'"'|[A-Za-z_][A-Za-z0-9_]*)/)) {
      d = substr(line, RSTART, RLENGTH)
      line = substr(line, RSTART + RLENGTH)
      sub(/^<<-?[ \t]*/, "", d)
      gsub(/["'"'"']/, "", d)
      if (d != "") { delim = d; skip = 1 }
    }
  }
  # ---- pass 2: lex, tracking quote state ----------------------------------
  END {
    n = length(buf); q = ""; tok = ""; have = 0
    for (i = 1; i <= n; i++) {
      c = substr(buf, i, 1)
      if (q != "") { if (c == q) q = ""; else { tok = tok c; have = 1 } ; continue }
      if (c == "\"" || c == "'"'"'") { q = c; have = 1; continue }
      if (c == "\\") { i++; tok = tok substr(buf, i, 1); have = 1; continue }
      if (c == " " || c == "\t" || c == "\n") { if (have) { print "W" tok; tok = ""; have = 0 } ; continue }
      if (c == ">") {
        if (have) { print "W" tok; tok = ""; have = 0 }
        if (substr(buf, i + 1, 1) == ">") { print "O>>"; i++ } else { print "O>" }
        continue
      }
      if (c == "|" || c == ";" || c == "&") {
        if (have) { print "W" tok; tok = ""; have = 0 }
        print "O;"
        continue
      }
      tok = tok c; have = 1
    }
    if (have) print "W" tok
  }
')"

targets=""
add() { targets="$targets
$1"; }

verb=""       # the write command whose arguments are being collected
redirect=0    # the next word is a redirect target
sedi=0        # this sed carries -i, so its file arguments are overwritten
lastarg=""    # for cp/mv/install/ln, only the final argument is written to

flush_last() { [ -n "$lastarg" ] && add "$lastarg"; lastarg=""; }

while IFS= read -r line; do
  [ -n "$line" ] || continue
  kind="${line%%"${line#?}"}"       # first character: W or O
  val="${line#?}"

  if [ "$kind" = O ]; then
    case "$val" in
      '>'|'>>') redirect=1 ;;
      *) flush_last; verb=""; redirect=0; sedi=0 ;;
    esac
    continue
  fi

  if [ "$redirect" -eq 1 ]; then add "$val"; redirect=0; continue; fi

  case "$val" in
    sed|gsed)                        flush_last; verb=sed;  sedi=0; continue ;;
    tee|rm|truncate|touch|chmod|chown|shred|mkdir)
                                     flush_last; verb=all;  continue ;;
    cp|mv|install|ln|rsync)          flush_last; verb=last; continue ;;
    dd)                              flush_last; verb=dd;   continue ;;
  esac

  case "$verb" in
    sed)  case "$val" in
            -i|-i*|--in-place*) sedi=1 ;;
            -*) ;;
            *) [ "$sedi" -eq 1 ] && add "$val" ;;
          esac ;;
    all)  case "$val" in -*) ;; *) add "$val" ;; esac ;;
    last) case "$val" in -*) ;; *) lastarg="$val" ;; esac ;;
    dd)   case "$val" in of=*) add "${val#of=}" ;; esac ;;
  esac
done <<EOF
$tokens
EOF
flush_last

pkg=""
hit=""
while IFS= read -r t; do
  [ -n "$t" ] || continue
  p="$(package_of "$t")"
  [ -n "$p" ] || continue
  pkg="$p"; hit="$t"; break
done <<EOF
$targets
EOF

[ -n "$pkg" ] || allow

deny "That command writes to $hit, which is inside the '$pkg' stow package — and
this checkout is the one \$HOME points at. The file goes live the moment it is
written, before any git command runs. Routing the write through sed, tee or a
redirect instead of the Edit tool does not change that; it only changes which
guard sees it.

Do it in a worktree instead:
    git wt new <branch>
then write to ../dotfiles-wt/<branch>/..., and when it is ready:
    git wt promote <branch>

If it could affect shell latency, measure it there first:
    ./measure/compare.sh ../dotfiles-wt/<branch>"
