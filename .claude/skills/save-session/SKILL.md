---
name: save-session
description: Mid-session checkpoint — snapshot current decisions and progress without archiving or cleaning up. Use when the user says "/save", "checkpoint", "save progress", "jot it down", "jot that down", "make a note", "note that", or before risky operations like schema migrations, large refactors, or long-running tasks.
---

# Save Session

Mid-session checkpoint. Captures current progress and decisions without the full end-of-session routine. Does **not** archive, move roadmap items, or propose commits.

Use before risky operations (migrations, large refactors) or when you want to preserve state before a `/clear`.

## Two modes

- **Checkpoint** (`/save`, "checkpoint", "save progress") — snapshot of progress so far plus what's next. Use `--type checkpoint` with `--next`.
- **Note** ("jot it down", "jot that down", "make a note", "note that") — a single observation, idea, or reminder to capture without the full checkpoint ceremony. Use `--type note`, skip `--next`, skip the recent-context read. Just write it and confirm.

---

## Steps (checkpoint mode)

### 0 — Get context

Run `date` to get the current time.

Determine the project name and branch:

```bash
PROJECT=$(jotter project)
BRANCH=$(jotter branch)
```

### 1 — Read recent context

First check whether a log exists for this project/branch — cheaper than letting `tail` error:

```bash
jotter ls --project "$PROJECT"
```

If the branch isn't listed, skip the read (nothing to duplicate) and go straight to step 2. Otherwise:

```bash
jotter tail --project "$PROJECT" --branch "$BRANCH" --limit 3
```

Review the last few entries to understand what's already been captured — avoid duplicating.

### 2 — Write the checkpoint

```bash
jotter write \
  --project "$PROJECT" \
  --branch "$BRANCH" \
  --type checkpoint \
  --content "<progress since last entry, decisions made, current state>" \
  --next "<what you're about to do next>"
```

Keep it concise — a few bullet points per topic. This is a snapshot, not a session summary.

### 3 — Confirm

> "Checkpoint saved at HH:MM. Safe to `/clear` or continue."

Do **not** propose commits, update the roadmap, or archive anything. That's `/finish`'s job.

## Steps (note mode)

For "jot it down" / "make a note" style requests, skip the tail read and write a single-line note:

```bash
jotter write \
  --project "$PROJECT" \
  --branch "$BRANCH" \
  --type note \
  --content "<the thing to remember>"
```

Then confirm: `> "Noted."`

No `--next`, no progress summary — just capture the thought and move on.
