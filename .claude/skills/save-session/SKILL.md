---
name: save-session
description: Mid-session checkpoint — snapshot current decisions and progress into SESSION.md without archiving or cleaning up. Use when the user says "/save", "checkpoint", "save progress", or before risky operations like schema migrations, large refactors, or long-running tasks.
---

# Save Session

Mid-session checkpoint. Captures current progress and decisions in SESSION.md without the full end-of-session routine. Does **not** archive, move roadmap items, or propose commits.

Use before risky operations (migrations, large refactors, Playwright runs) or when you want to preserve state before a `/clear`.

---

## Steps

### 0 — Get the current time

Run `date` to timestamp the checkpoint accurately.

---

### 1 — Read current SESSION.md

Read `SESSION.md` to understand the existing session note structure. If there's already a session note for today, you'll be appending to it — not replacing it.

---

### 2 — Write the checkpoint

In `SESSION.md`, update the current session note block (`## Session note — YYYY-MM-DD`) with a `### Checkpoint — HH:MM` sub-heading. Under it, write:

- **Progress so far** — what's been built, fixed, or changed since the session started (or since the last checkpoint)
- **Decisions made** — any choices settled during this segment, with brief reasoning
- **Current state** — where things stand right now: what's working, what's half-done, any dirty git state worth noting
- **Next steps** — what you're about to do next (useful context if the session crashes or `/clear` is run)

Keep it concise — this is a snapshot, not a session summary. A few bullet points per section is enough.

If there's already a checkpoint from earlier in the session, leave it in place and add the new one below it. Checkpoints are append-only within a session.

---

### 3 — Confirm

Report back briefly:

> "Checkpoint saved in SESSION.md at HH:MM. Safe to `/clear` or continue."

Do **not** propose commits, update the roadmap, or archive anything. That's `/finish`'s job.
