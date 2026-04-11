---
name: finish-session
description: Run the end-of-session checklist — write session summary to session log, move completed items to DONE.md, add new items to ROADMAP.md, check CLAUDE.md is current, review dirty git state and propose commits. Use when the user says "/finish", "/finish-session", "/end", "let's wrap up", "wrap up", "let's finish", "end this session", "let's call it", "that's enough for today", or similar.
---

# Finish Session

Runs the end-of-session checklist. Ensures every session ends cleanly with the handoff state captured for next time.

**Mid-session break (`/break`)?** Use the `break-session` skill instead.

---

## Steps

### 0 — Get context

Run `date` to get the actual current time. Check whether the session is running past 7PM — if so, flag it.

Determine the project name and branch:

```bash
basename "$(git rev-parse --show-toplevel)"
git rev-parse --abbrev-ref HEAD
```

---

### 1 — Write the finish entry

Summarise the session — what was built or fixed, key decisions, anything discovered that changed the plan. The `--next` field is the handover: the 2-3 most important things to pick up next session, in priority order.

```bash
session_logger.py write \
  --project <project> \
  --branch <branch> \
  --type finish \
  --content "<session summary: what shipped, decisions made, gotchas/debt>" \
  --next "<top priorities for next session, in order>"
```

This auto-commits and pushes to the data repo remote.

---

### 2 — Move completed items to DONE.md

Scan `ROADMAP.md` for any `- [x]` items (or items completed this session). Move them to the top of `DONE.md` under today's date heading. Remove them from `ROADMAP.md`.

---

### 3 — Add new items

Anything discovered during the session that needs doing:
- New task for the active sprint → add to `ROADMAP.md` **Now**
- Agreed next priority → add to `ROADMAP.md` **Next**
- Backlog idea / later item → add to `ROADMAP.md` **Later** (or `BACKLOG.md` if detailed)

Don't leave it to memory.

---

### 4 — Update roadmap horizons

In `ROADMAP.md`:
- If a **Next** item was started this session, move it to **Now**
- If priorities shifted, reorder accordingly
- If a **Later** item is now ready to start, check it has a spec in `docs/specs/` before moving to **Next**

---

### 5 — Update CLAUDE.md

If anything changed — new script, renamed column, updated workflow, new skill, schema change — update the relevant section of the project's `CLAUDE.md`. Future sessions start by reading it; stale docs are worse than no docs.

---

### 6 — Update open PR TODO checklists

Check for any open PRs on the current branch or any feature branches worked on this session:

```bash
gh pr list --state open
```

For each open PR, review what's left to do and add any remaining TODOs as a checklist at the bottom of the PR description under a `## TODO before merge` heading. This makes the PR a live tracker of what's left, so the next session picks up exactly where things left off.

---

### 7 — Check dirty state and propose commits

```bash
git status
git diff --stat
```

Survey all uncommitted changes. Propose a grouping to the user — one commit per logical feature or change. Wait for approval before staging or committing.

---

### 8 — Final check

Once commits are done:

```bash
git status
```

Tree should be clean. If not, flag any remaining uncommitted files and ask whether to commit, stash, or leave.

Confirm push if not already done.

Cancel the session cron timer if one is running (`CronDelete <job-id>`).

---

## Sign-off

End with a one-line summary of the session:

> "Done. Today: [what shipped]. Next session: [top priority]."
