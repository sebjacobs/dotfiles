---
name: finish-session
description: Run the end-of-session checklist — write session summary to session log, move completed items to DONE.md, add new items to ROADMAP.md, check CLAUDE.md is current, review dirty git state and propose commits. Use when the user says "/finish", "/finish-session", "/end", "let's wrap up", "wrap up", "let's finish", "end this session", "let's call it", "that's enough for today", or similar.
---

# Finish Session

End-of-session checklist. Captures the handoff and leaves a clean tree.

**Mid-session break (`/break`)?** Use `break-session` instead.

---

## Defaults

- **Tight by default.** Bullets, not prose. Short jotter content, short commit bodies. Expand only where something genuinely needs explanation.
- **Detect, don't ask.** Probe for tracker files and remotes; skip irrelevant steps silently. Don't run a step just to confirm it doesn't apply.

---

## Steps

### 0 — Context

```bash
PROJECT=$(jotter project)
BRANCH=$(jotter branch)
[ -f ROADMAP.md ] && HAS_ROADMAP=1 || HAS_ROADMAP=0
git remote -v | grep -q github.com && HAS_GITHUB=1 || HAS_GITHUB=0
```

### 1 — Write the finish entry

Bullets. Cover what shipped, key decisions, anything that changed the plan. `--next` is the handover — 2-3 priorities, in order.

```bash
jotter write --project "$PROJECT" --branch "$BRANCH" --type finish \
  --content "<bullet summary>" --next "<top priorities>"
```

Auto-commits and pushes.

### 2 — Update the project tracker (if `HAS_ROADMAP`)

- Move completed items from `ROADMAP.md` to today's date in `DONE.md`
- Add anything discovered this session (Now / Next / Later)
- Move started **Next** items to **Now**; promote ready **Later** items if they have a spec

Skip this step entirely if `ROADMAP.md` is absent — the project uses a different convention (e.g. `TODO.md`), and that's handled by the project's own CLAUDE.md.

### 3 — Update project CLAUDE.md

If anything changed — new script, renamed column, updated workflow, new skill, schema change — update the relevant section. Skip if nothing meaningful changed.

### 4 — Open PR checklists (if `HAS_GITHUB`)

```bash
gh pr list --state open
```

For each open PR touched this session, refresh the `## TODO before merge` checklist. Skip the whole step when `HAS_GITHUB=0`.

### 5 — Dirty state and commits

```bash
git status
git diff --stat
```

Propose a grouping, wait for approval. One commit per logical change. Tight messages — long bodies are the exception, not the default.

### 6 — Final check

```bash
git status
```

Tree should be clean. Confirm push.

If this session set a cron timer (via `/start`), cancel it now. **Do not** call `CronList` to fish for one — only cancel if you already know the job-id from this session.

---

## Sign-off

> "Done. Today: [what shipped]. Next session: [top priority]."
