---
name: finish-session
description: Run the end-of-session checklist — commit any dirty work, write a finish entry to the jotter log, cancel the session cron timer. Leaves a walk-away state. Use when the user says "/finish", "/finish-session", "/end", "let's wrap up", "wrap up", "let's finish", "end this session", "let's call it", "that's enough for today", or similar.
---

# Finish Session

End-of-session wrap-up. **Walk-away guarantee:** when this skill completes, the laptop can be closed — dirty work is committed, the log entry is written, the cron timer is cancelled, and no further actions follow.

**Mid-session checkpoint or stepping away briefly?** Use `/save` instead. **Just jotting a note?** Use `/note`.

**Want ROADMAP / DONE.md / CLAUDE.md curation?** That used to live here but is now out of scope — do it before invoking `/finish`, or run a dedicated `/tracker`-style skill if you have one.

---

## Defaults

- **Tight by default.** Bullets, not prose. Short jotter content, short commit bodies.
- **ASAP.** Minimal back-and-forth — one commit-grouping proposal, one log preview, done.

---

## Steps

### 0 — Context

```bash
PROJECT=$(jotter project)
BRANCH=$(jotter branch)
```

### 1 — Commit dirty work

```bash
git status
git diff --stat
```

If the tree is clean, skip to step 2.

Otherwise propose a grouping (one commit per logical change), wait for approval, commit. These are proper end-of-session commits — not WIP. Tight messages.

### 2 — Preview the finish entry

Render the draft back to the user as a quoted block. Bullets cover what shipped (referencing the commits just made), key decisions, anything that changed the plan. `--next` is the handover — 2-3 priorities, in order.

> **Content:**
> - <bullet 1: what shipped>
> - <bullet 2: key decision>
>
> **Next:**
> - <priority 1>
> - <priority 2>

### 3 — Write — final log action

```bash
jotter write --project "$PROJECT" --branch "$BRANCH" --type finish \
  --content "<bullets from preview>" --next "<priorities from preview>"
```

Auto-commits and pushes the data repo.

### 4 — Cancel session timer

If this session set a cron timer (via `/start`), cancel it now with `CronDelete <job-id>`. **Do not** call `CronList` to fish for one — only cancel if you already know the job-id from this session.

### 5 — Sign-off

> "Done at HH:MM. Tree clean, log written, timer cancelled. Safe to close the laptop."
