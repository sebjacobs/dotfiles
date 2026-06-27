---
name: stop-session
description: Run the end-of-session checklist — commit any dirty work, write a stop entry to the jotter log, cancel the session cron timer. Leaves a walk-away state. Use when the user says "/stop", "let's stop for today", "let's stop for the morning", "let's wrap up", "wrap up", "end this session", "let's call it", "that's enough for today", or the legacy "/finish".
---

# Stop Session

End-of-session wrap-up. **Walk-away guarantee:** when this skill completes, the laptop can be closed — dirty work is committed, the log entry is written, the cron timer is cancelled, and no further actions follow.

A `stop` ends a *work session*, not a branch — you'll stop a branch many times before it's done. When a feature branch is finished for good, use `/handover` to distil it onto main. (`stop` was previously `finish`; `/finish` still triggers this skill and `--type finish` still works.)

**Mid-session checkpoint or stepping away briefly?** Use `/save` instead. **Just jotting a note?** Use `/note`.

**Want ROADMAP / DONE.md / CLAUDE.md curation?** That used to live here but is now out of scope — do it before invoking `/stop`, or run a dedicated `/tracker`-style skill if you have one.

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

### 2 — Preview the stop entry

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
jotter write --project "$PROJECT" --branch "$BRANCH" --type stop \
  --content "<bullets from preview>" --next "<priorities from preview>"
```

Commits the data repo locally; the push is asynchronous, carried to the remote by the background timer (`jotter daemon`). Force it now with `jotter sync` if you need it pushed before walking away.

### 4 — Cancel session timer

If this session set a cron timer (via `/start`), cancel it now with `CronDelete <job-id>`. **Do not** call `CronList` to fish for one — only cancel if you already know the job-id from this session.

### 5 — Sign-off

> "Done at HH:MM. Tree clean, log written, timer cancelled. Safe to close the laptop."
