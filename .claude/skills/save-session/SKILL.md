---
name: save-session
description: Mid-session checkpoint — commit any dirty work, snapshot decisions and progress to the jotter log. Walk-away guarantee. Use when the user says "/save", "checkpoint", "save progress", "jot it down", "jot that down", "make a note", "note that", or before risky operations like schema migrations, large refactors, or long-running tasks.
---

# Save Session

Mid-session checkpoint. **Walk-away guarantee for the checkpoint mode:** when the skill completes, dirty work is committed and the log entry is written — safe to `/clear`, walk away, or continue.

Use before risky operations (migrations, large refactors) or before `/clear`.

---

## Defaults

- **Tight by default.** Bullets, not prose. A few lines per topic — this is a snapshot, not a session summary.
- **Don't pre-read.** Skip `jotter tail` / `jotter ls`. A duplicate checkpoint is cheaper than two extra reads on every save.
- **ASAP.** One commit-grouping proposal, one log preview, done.

---

## Two modes

### Checkpoint (`/save`, "checkpoint", "save progress")

Progress so far plus what's next.

**1. Commit dirty work**

```bash
git status
git diff --stat
```

If the tree is clean, skip to step 2. Otherwise propose a grouping, wait for approval, commit. These are proper commits — not WIP (use `/break` for WIP).

**2. Preview the checkpoint**

> **Content:**
> - <bullet 1>
> - <bullet 2>
>
> **Next:** <what's next>

**3. Write — final log action**

```bash
jotter write \
  --project "$(jotter project)" --branch "$(jotter branch)" \
  --type checkpoint \
  --content "<bullets from preview>" \
  --next "<next from preview>"
```

**4. Confirm:** `> "Checkpoint saved at HH:MM. Tree clean, log written. Safe to /clear or continue."`

### Note ("jot it down", "make a note", "note that")

Single observation, no handover, no commit. Just a casual jot.

**1. Preview**

> **Note:** <the thing to remember>

**2. Write — final action**

```bash
jotter write \
  --project "$(jotter project)" --branch "$(jotter branch)" \
  --type note \
  --content "<note from preview>"
```

**3. Confirm:** `> "Noted at HH:MM."`
