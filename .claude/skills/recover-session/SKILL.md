---
name: recover-session
description: Recover context from a crashed or unfinished session by reading the most recent JSONL transcript. Use when the user says "/recover", "recover session", "what was I doing", or when /start detects the last entry isn't a finish.
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

### 1 — Find the transcript

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

### 2 — Extract the conversation

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
