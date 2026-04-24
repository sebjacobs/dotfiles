---
name: recover-session
description: Recover context from a crashed or unfinished session — check jotter logs first, fall back to Claude Code's raw JSONL transcript only if the jotter entries don't cover what happened. Use when the user says "/recover", "recover session", "what was I doing", or when /start detects the last entry isn't a finish.
---

# Recover Session

Retrospective summary from Claude Code's JSONL session transcript. Use after a crash, unexpected exit, or any session that ended without running `/finish` — reconstructs what happened and writes a recovery entry to the session log so the next session can pick up cleanly.

---

## Steps

### 0 — Detect the situation

Determine the project name and branch:

```bash
PROJECT=$(jotter project)
BRANCH=$(jotter branch)
```

Check the last session log entry:

```bash
jotter tail --project "$PROJECT" --branch "$BRANCH" --limit 1
```

If the last entry is a `finish`, the session ended cleanly — nothing to recover. Tell the user and stop.

If the last entry is `start`, `checkpoint`, or `break`, the previous session likely crashed or the user forgot `/finish` — proceed to step 1.

**If there are no jotter entries at all for this project/branch, skip step 1 and go straight to step 2.** There is nothing for jotter to cover, so the transcript is the only source. Do not interpret "no entries" as "nothing to recover" — the whole point of `/recover` is that `/finish` didn't run.

---

### 1 — Try jotter first

Before reaching for the raw Claude Code transcript, check whether jotter already has enough to reconstruct the session. A checkpoint entry usually captures the substance — `/save` writes one whenever a thread concludes.

Pull recent entries for the branch:

```bash
jotter tail --project "$PROJECT" --branch "$BRANCH" --limit 3
```

If the session spans a known date, widen the window across the whole project to catch work on other branches:

```bash
jotter ls --project "$PROJECT" --since YYYY-MM-DD --until YYYY-MM-DD
jotter search --project "$PROJECT" --since YYYY-MM-DD --until YYYY-MM-DD ""
```

(`--since`/`--until` accept `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM:SS`.)

If the jotter entries fully cover what happened — you can answer "what was built, what decisions were made, where did it stop" without the transcript — **skip straight to step 3** and write the recovery entry from the jotter content. Tell the user you're doing so.

Otherwise fall back to the transcript (step 2). The bar for "jotter covers it" is high — if there's no checkpoint, the checkpoint stops well before the crash, or you're unsure whether it covers the full session, go to step 2. When in doubt, read the transcript; skipping it is the failure mode this skill exists to prevent.

---

### 2 — Find and extract the transcript (fallback)

The skill ships a helper at `scripts/transcript.py` that lists recent JSONLs and extracts human/assistant turns. Use it — do not re-derive the project-dir path or re-implement the filter inline.

List recent transcripts for the current repo, with modified time and first user message:

```bash
~/.claude/skills/recover-session/scripts/transcript.py list
```

Show the top result to the user and ask: "Is this the session to recover from, or should I look at an older one?" Wait for confirmation.

Then extract the chosen transcript (skips `tool_use`, `tool_result`, snapshots, etc.) and read it:

```bash
~/.claude/skills/recover-session/scripts/transcript.py extract <path-to-jsonl>
# writes /tmp/recovered-session.md by default; pass --out to override
```

Read `/tmp/recovered-session.md` to understand what happened.

---

### 3 — Write the recovery entry

From the extracted conversation, synthesise a recovery entry:

```bash
jotter write \
  --project "$PROJECT" \
  --branch "$BRANCH" \
  --type finish \
  --content "<what was built/fixed, key decisions, where things stopped>" \
  --next "<priorities inferred from the session trajectory>"
```

Use `--type finish` so the log correctly marks the session as closed.

---

### 4 — Report

> "Recovered session from [date/time]. Key context: [1-2 sentence summary]. Ready to continue with `/start`."

Flag anything that couldn't be recovered (very short session, mostly tool output with little conversation).
