---
name: save-session
description: Mid-session checkpoint — snapshot current decisions and progress without archiving or cleaning up. Use when the user says "/save", "checkpoint", "save progress", "jot it down", "jot that down", "make a note", "note that", or before risky operations like schema migrations, large refactors, or long-running tasks.
---

# Save Session

Mid-session checkpoint. Captures progress without the full end-of-session routine. Does **not** archive, commit, or update the roadmap — that's `/finish`'s job.

Use before risky operations (migrations, large refactors) or before `/clear`.

---

## Defaults

- **Tight by default.** Bullets, not prose. A few lines per topic — this is a snapshot, not a session summary.
- **Don't pre-read.** Skip `jotter tail` / `jotter ls`. A duplicate checkpoint is cheaper than two extra reads on every save.

---

## Two modes

### Checkpoint (`/save`, "checkpoint", "save progress")

Progress so far plus what's next.

```bash
jotter write \
  --project "$(jotter project)" --branch "$(jotter branch)" \
  --type checkpoint \
  --content "<progress, decisions, current state — bullets>" \
  --next "<what's next>"
```

Confirm: `> "Checkpoint saved at HH:MM. Safe to /clear or continue."`

### Note ("jot it down", "make a note", "note that")

Single observation, no handover.

```bash
jotter write \
  --project "$(jotter project)" --branch "$(jotter branch)" \
  --type note \
  --content "<the thing to remember>"
```

Confirm: `> "Noted."`
