# measure/

Finds where **your** agent sessions lose turns. Nothing here is generic advice:
it reads your own transcripts and reports your own profile.

```bash
./measure/analyze.py                       # defaults to this repo's project dir
./measure/analyze.py ~/.claude/projects/<project>
```

## ⚠️ It reads private data

Claude Code transcripts under `~/.claude/projects/**` contain your prompts,
file paths, project names and command output. `analyze.py`:

- **reads** them locally,
- **never** sends anything anywhere,
- **prints** aggregates that can still include paths and project names.

Do not paste its output into a public issue without reading it first. Nothing
in this repo uploads, uploads-by-default, or phones home.

## What it reports, and why each number

| Metric | Why it is the one that matters |
|---|---|
| **Rework turns** | A failure the agent absorbs costs 1 turn; one that triggers 3 retries costs 4. Counting errors alone hides that difference |
| Failures by cause | Separates what you can fix from what is your own guard working correctly |
| Output volume by tool | Every character read is context spent. This is usually far larger than the failure cost |
| Command duration | Tells you where a "notify me when done" threshold belongs, instead of guessing |

## Reading the output honestly

**Not every failure is waste.** On the machine this repo came from, the single
largest failure bucket was the owner's own `PreToolUse` guards denying commands
by design. That is the system working, and "fixing" it would break it.

**Beware the long tail.** 582 of 1,344 failures had no shared cause — the most
common single form appeared 18 times. When the tail looks like that, there is
no big lever hiding in it, and looking for one wastes your time.

**Volume beats failures.** The same measurement found ~26 rework turns from
shell misconfiguration, against ~9 M tokens of tool output. The second number
is the one worth attacking, and it is not attacked by fixing aliases.
