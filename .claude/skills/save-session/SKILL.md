---
name: save-session
description: Mid-session checkpoint or step-away — WIP-commit any dirty work, snapshot progress and what's next to the jotter log. Walk-away guarantee. Use when the user says "/save", "checkpoint", "save progress", "taking a break", "stepping away", "back in a bit", "pausing", or before risky operations like schema migrations, large refactors, or long-running tasks. For a casual note without committing use `/note`; for end of session use `/stop`.
---

# Save Session

Mid-session checkpoint, also used for stepping away. **Walk-away guarantee:** when the skill completes, dirty work is committed and the log entry is written — safe to `/clear`, walk away, or continue.

Use before risky operations (migrations, large refactors), before `/clear`, or when stepping away briefly. For a casual note with no commit, use `/note`. For end of session, use `/stop`.

---

## Defaults

- **Tight by default.** Bullets, not prose. A few lines per topic — this is a snapshot, not a session summary.
- **Don't pre-read.** Skip `jotter tail` / `jotter ls`. A duplicate checkpoint is cheaper than two extra reads on every save.
- **ASAP.** One WIP commit, one log preview, done — no commit-grouping discussion.

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

If the tree is clean, skip to step 2. Otherwise stage everything and commit as a single WIP commit — **do not propose groupings, do not wait for approval.** This is a walk-away checkpoint; ceremony defeats the purpose. Atomic grouping belongs at PR time, where the WIP commit will be amended/split.

```bash
git add -A
git commit -m "WIP: checkpoint at $(date +%H:%M)"
```

Push only if the branch already tracks a remote — otherwise leave it local.

### 2 — Preview the checkpoint

> **Content:**
> - <bullet 1>
> - <bullet 2>
>
> **Next:** <what's next>

### 3 — Write — final log action

```bash
jotter write \
  --project "$PROJECT" --branch "$BRANCH" \
  --type checkpoint \
  --content "<bullets from preview>" \
  --next "<next from preview>"
```

### 4 — Cancel session timer — only if stepping away

If the user is stepping away ("taking a break", "back in a bit", "pausing") **and** a session cron timer is running, cancel it with `CronDelete <job-id>`. **Do not** call `CronList` to fish for one — only cancel if you already know the job-id from this session. If the user is checkpointing to continue, leave the timer running.

### 5 — Confirm

> "Checkpoint saved at HH:MM. Tree clean, log written. Safe to /clear, walk away, or continue."
