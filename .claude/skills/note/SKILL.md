---
name: note
description: Jot a single ad-hoc note to the jotter log — no commit, no handover, no timer change. Use when the user says "/note", "jot it down", "jot that down", "make a note", "note that", or wants to quickly capture an observation without checkpointing the session.
---

# Note

A casual jot. One observation, captured durably to the jotter log. **No commit, no handover, no timer change** — this does not checkpoint the session. For a walk-away checkpoint use `/save`; for end-of-session use `/stop`.

---

## Steps

### 1 — Preview

> **Note:** <the thing to remember>

### 2 — Write — final action

```bash
jotter write \
  --project "$(jotter project)" --branch "$(jotter branch)" \
  --type note \
  --content "<note from preview>"
```

### 3 — Confirm

> "Noted at HH:MM."
