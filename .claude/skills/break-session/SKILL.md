---
name: break-session
description: Save mid-session state before a break — auto-WIP-commit any dirty work, write a break entry to the jotter log, cancel the session cron timer. Walk-away guarantee in under 30 seconds. Use when the user says "/break", "taking a break", "let's take a break", "back in a bit", "stepping away", "pausing", or similar.
---

# Break Session

Quick wrap before stepping away. **Walk-away guarantee:** when this skill completes, the laptop can be closed — dirty work is committed (as a single WIP commit, no ceremony), the log entry is written, the cron timer is cancelled.

Optimised for ASAP: no commit grouping discussion, no proper messages. Just stash state durably so you can resume on return.

---

## Steps

### 0 — Context

```bash
PROJECT=$(jotter project)
BRANCH=$(jotter branch)
```

### 1 — WIP-commit dirty work

```bash
git status --short
```

If the tree is clean, skip to step 2.

Otherwise stage everything and commit as a single WIP commit — **do not propose groupings, do not wait for approval.** The user is walking away; ceremony defeats the purpose. The WIP commit will be amended/split on return.

```bash
git add -A
git commit -m "WIP: break at $(date +%H:%M)"
```

Push only if the branch already tracks a remote — otherwise leave it local.

### 2 — Preview the break entry

> **Content:**
> - <what's been done, current state, anything half-finished>
>
> **Next:** <what to pick up on return>

### 3 — Write — final log action

```bash
jotter write \
  --project "$PROJECT" \
  --branch "$BRANCH" \
  --type break \
  --content "<content from preview>" \
  --next "<next from preview>"
```

### 4 — Cancel session timer

If a session cron timer is running, cancel it with `CronDelete <job-id>`. **Do not** call `CronList` to fish for one — only cancel if you already know the job-id from this session. `/start` will set a fresh one on return.

### 5 — Confirm

> "Break saved at HH:MM. WIP committed, log written, timer cancelled. Close the laptop — run `/start` when you're back."
