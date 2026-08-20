#!/usr/bin/env python3
"""Measure agent FRICTION in Claude Code transcripts.

It does not count errors. It counts REWORK: a failure the agent absorbs costs
one turn; a failure that triggers three retries of the same intent costs four.
The second is the one that hurts, and error counts hide the difference.

Usage:  ./analyze.py [PROJECT_DIR]
        PROJECT_DIR defaults to the newest directory under ~/.claude/projects/
"""
import json, glob, os, sys, re, collections
from datetime import datetime

def _default_dir():
    """Newest project under ~/.claude/projects — no path is hardcoded here."""
    root = os.path.expanduser("~/.claude/projects")
    cands = [os.path.join(root, d) for d in os.listdir(root)] if os.path.isdir(root) else []
    cands = [c for c in cands if os.path.isdir(c) and glob.glob(f"{c}/*.jsonl")]
    if not cands:
        sys.exit(f"no transcripts found under {root} — pass a directory explicitly")
    return max(cands, key=os.path.getmtime)

D = sys.argv[1] if len(sys.argv) > 1 else _default_dir()

def ts(s):
    try: return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception: return None

PREFIXOS = {"cd","command","sudo","env","timeout","nohup","exec","builtin","then","do","done",
            "if","fi","for","while","set","export","local","source",".","time","xargs","nice"}

def familia(nome, inp):
    """Approximate intent. For Bash, the VERB of the command.

    Skips prefixes AND their arguments: an earlier version treated the argument
    of `cd` as the command, and whole families came out named after directories.
    """
    if nome != "Bash": return nome
    cmd = (inp or {}).get("command", "").strip()
    if not cmd: return "(vazio)"
    toks = re.split(r"\s+", cmd)
    i = 0
    while i < len(toks):
        t = toks[i].strip("()`\"';")
        if not t: i += 1; continue
        if "=" in t and not t.startswith("-"):      # VAR=valor
            i += 1; continue
        base = os.path.basename(t)
        if base in PREFIXOS:
            i += 1
            # skip the prefix's own argument when it is a path or a flag
            while i < len(toks) and (toks[i].startswith("-") or "/" in toks[i]
                                     or toks[i].startswith("$") or toks[i] in {"&&",";"}):
                i += 1
            continue
        if t.startswith("-") or t in {"&&","||",";","|"}: i += 1; continue
        if base.startswith("$"): return "(variável)"
        return base
    return "(vazio)"

chamadas = 0
por_ferramenta = collections.Counter()
falhas_por_familia = collections.Counter()
total_por_familia = collections.Counter()
rework = collections.Counter()          # family -> number of EXTRA attempts
time_lost = collections.Counter()       # family -> seconds spent in failed calls
reasons = collections.Counter()
other_detail = collections.Counter()
sessions_with_friction = collections.defaultdict(set)

MOTIVO = [
 ("permission: prompt or denied", r"Permission to use|requested permissions|denied by the Claude Code"),
 ("a guard of your own denied it", r"harness|ADR 00\d\d|negado por padrão|rpia-[a-z-]+gate"),
 ("you rejected the call",      r"user doesn't want to proceed"),
 ("alias shadowing a POSIX tool", r"--icons|Usage: bat|Usage: eza|--style <THEME>|unknown encoding"),
 ("path does not exist",        r"No such file or directory|does not exist"),
 ("shell syntax",               r"syntax error|parse error|unmatched|no matches found|nonterminated"),
 ("timeout",                   r"timed out|timeout"),
 ("Edit: anchor did not match", r"String to replace not found|has not been read yet"),
 ("MCP: invalid argument",      r"MCP error|Input validation error"),
]

for fp in sorted(glob.glob(f"{D}/*.jsonl")):
    sid = os.path.basename(fp)[:8]
    usos = {}          # id -> (nome, familia, timestamp)
    eventos = []       # (ordem, familia, falhou)
    with open(fp, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if '"tool_use"' not in line and '"tool_result"' not in line: continue
            try: d = json.loads(line)
            except Exception: continue
            t, msg = d.get("type"), d.get("message") or {}
            cont = msg.get("content")
            if not isinstance(cont, list): continue
            for c in cont:
                if not isinstance(c, dict): continue
                if t == "assistant" and c.get("type") == "tool_use":
                    f = familia(c.get("name"), c.get("input"))
                    usos[c.get("id")] = (c.get("name"), f, ts(d.get("timestamp")))
                    chamadas += 1; por_ferramenta[c.get("name")] += 1; total_por_familia[f] += 1
                elif t == "user" and c.get("type") == "tool_result":
                    u = usos.get(c.get("tool_use_id"))
                    if not u: continue
                    nome, f, t0 = u
                    txt = c.get("content")
                    if isinstance(txt, list):
                        txt = " ".join(x.get("text","") for x in txt if isinstance(x, dict))
                    txt = txt if isinstance(txt, str) else ""
                    falhou = bool(c.get("is_error")) or bool(re.search(r"^Exit code [1-9]|rror", txt[:200]))
                    eventos.append((f, falhou))
                    if falhou:
                        falhas_por_familia[f] += 1
                        sessions_with_friction[f].add(sid)
                        t1 = ts(d.get("timestamp"))
                        if t0 and t1: time_lost[f] += (t1 - t0).total_seconds()
                        for nome_m, rx in MOTIVO:
                            if re.search(rx, txt[:600]): reasons[nome_m] += 1; break
                        else:
                            chave = re.sub(r"[0-9]+","N", txt[:70]).strip().replace("\n"," ")
                            reasons["outro"] += 1
                            other_detail[chave] += 1

    # rework: after a failure, how many CONSECUTIVE calls of the same family followed
    i = 0
    while i < len(eventos):
        f, falhou = eventos[i]
        if falhou:
            j = i + 1; extras = 0
            while j < len(eventos) and eventos[j][0] == f:
                extras += 1
                if not eventos[j][1]: break     # it succeeded: stop counting
                j += 1
            if extras: rework[f] += extras
            i = j
        else: i += 1

print(f"  tool calls            : {chamadas:,}")
print(f"  failures              : {sum(falhas_por_familia.values()):,}"
      f"  ({100*sum(falhas_por_familia.values())/max(chamadas,1):.1f}%)")
print(f"  REWORK turns          : {sum(rework.values()):,}")
print(f"  time inside failed calls: {sum(time_lost.values())/60:.0f} min\n")

print("  WHY IT FAILED")
for m, n in reasons.most_common():
    print(f"    {n:5d}  {m}")

print("\n  INSIDE 'other' — top 8")
for k, n in other_detail.most_common(8):
    print(f"    {n:5d}  {k[:84]}")

print("\n  WHERE THE REWORK IS (extra turns spent repeating the same intent)")
print(f"    {'family':<22}{'extra':>7}{'fail':>8}{'total':>8}{'rate':>7}{'sess':>9}")
for f, n in rework.most_common(14):
    tot = total_por_familia[f]; fal = falhas_por_familia[f]
    print(f"    {f:<22}{n:>7}{fal:>8}{tot:>8}{100*fal/max(tot,1):>6.0f}%{len(sessions_with_friction[f]):>9}")
