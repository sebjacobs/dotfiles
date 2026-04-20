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

If the last entry is `start`, `checkpoint`, or `break` (or there are no entries), the previous session likely crashed or the user forgot `/finish`.

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

Only fall back to the transcript (step 2) when jotter is thin: no checkpoint was written, the checkpoint stops well before the crash, or you need the literal back-and-forth to reconstruct a decision.

---

### 2 — Find the transcript (fallback)

```bash
PROJECT_DIR="$HOME/.claude/projects/$(pwd | sed 's|/|-|g')"
ls -lt "$PROJECT_DIR"/*.jsonl | head -5
```

Show the user the timestamp and first user message from the most recent transcript so they can confirm it's the right session:

```bash
LATEST=$(ls -t "$PROJECT_DIR"/*.jsonl | head -1)
stat -f "%Sm" "$LATEST"
python3 -c "
import json, sys
for line in open('$LATEST'):
    msg = json.loads(line)
    if msg.get('type') == 'user':
        content = msg.get('message', {}).get('content', '')
        if isinstance(content, str):
            print(content[:200])
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get('type') == 'text':
                    print(block['text'][:200])
                    break
        break
"
```

Ask the user: "Is this the session to recover from, or should I look at an older one?"

Wait for confirmation before proceeding.

---

### 2a — Extract the conversation (fallback)

Filter the JSONL to only human and assistant text turns — skip `tool_use`, `tool_result`, `file-history-snapshot`, `permission-mode`, and `attachment` entries:

```bash
python3 -c "
import json, sys

for line in open('$LATEST'):
    msg = json.loads(line)
    msg_type = msg.get('type')

    if msg_type == 'user':
        content = msg.get('message', {}).get('content', '')
        if isinstance(content, str) and content.strip():
            print(f'## User\n{content[:500]}\n')
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get('type') == 'text':
                    print(f'## User\n{block[\"text\"][:500]}\n')
                    break

    elif msg_type == 'assistant':
        content = msg.get('message', {}).get('content', '')
        if isinstance(content, str) and content.strip():
            print(f'## Assistant\n{content[:500]}\n')
        elif isinstance(content, list):
            texts = [b.get('text','') for b in content if isinstance(b, dict) and b.get('type') == 'text']
            combined = ' '.join(texts).strip()
            if combined:
                print(f'## Assistant\n{combined[:500]}\n')
" > /tmp/recovered-session.md
wc -l /tmp/recovered-session.md
```

Read the extracted conversation to understand what happened.

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
