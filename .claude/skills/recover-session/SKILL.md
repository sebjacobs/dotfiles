---
name: recover-session
description: Recover context from a crashed or unfinished session by reading the most recent JSONL transcript. Use when the user says "/recover", "recover session", "what was I doing", or when /start detects that SESSION.md is stale relative to the last session transcript.
---

# Recover Session

Retrospective summary from Claude Code's JSONL session transcript. Use after a crash, unexpected exit, or any session that ended without running `/finish` — reconstructs what happened and writes it into SESSION.md so the next session can pick up cleanly.

---

## Steps

### 0 — Identify the project hash

The current project's sessions are stored under `~/.claude/projects/`. The directory name is the absolute path with `/` replaced by `-` and leading `-`. For the current working directory, construct the path:

```bash
# Derive the project hash from cwd
PROJECT_DIR="$HOME/.claude/projects/$(pwd | sed 's|/|-|g')"
echo "$PROJECT_DIR"
ls -lt "$PROJECT_DIR"/*.jsonl | head -5
```

This lists the most recent JSONL files by modification time. The most recent one is likely the crashed session.

---

### 1 — Confirm the right session

Show the user the timestamp and first user message from the most recent JSONL file so they can confirm it's the right session to recover:

```bash
LATEST=$(ls -t "$PROJECT_DIR"/*.jsonl | head -1)
# Show file modification time
stat -f "%Sm" "$LATEST"
# Show first user message
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

### 2 — Extract the conversation

Filter the JSONL to only human and assistant text turns — skip `tool_use`, `tool_result`, `file-history-snapshot`, `permission-mode`, and `attachment` entries. This dramatically reduces noise.

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

### 3 — Synthesise into SESSION.md format

From the extracted conversation, write a session note covering:

- **What was built or fixed** — concrete outcomes, not process
- **Key decisions made** — with reasoning where recoverable
- **Where things stopped** — what was in progress when the session ended
- **Decisions for next session** — priorities inferred from the trajectory
- **Handover prompt** — a self-contained paragraph the next session can read cold

This follows the same format as `/finish` step 1, but reconstructed rather than live.

---

### 4 — Archive the old SESSION.md and write the recovery

If `SESSION.md` already exists and has content:

1. Check whether the existing content is stale (predates the recovered session). If so, it's from an even earlier session — preserve it by appending to `docs/session_log.md` before overwriting.
2. If the existing content is from the same date, merge the recovery into it rather than replacing.

Write the recovered session note to `SESSION.md`.

---

### 5 — Report

Summarise what was recovered:

> "Recovered session from [date/time]. Key context: [1-2 sentence summary]. Written to SESSION.md — ready to continue with `/start` or pick up directly."

Flag anything that couldn't be recovered (e.g. if the session was very short or mostly tool output with little conversation).
