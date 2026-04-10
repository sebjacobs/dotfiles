---
name: finish-session
description: Run the end-of-session checklist — update session note in SESSION.md, move completed items to DONE.md, add new items to ROADMAP.md or BACKLOG.md, check CLAUDE.md is current, review dirty git state and propose commits. Also handles mid-session breaks (/break) in quick mode: steps 0, 1, and 8 only. Use when the user says "/finish", "/finish-session", "/end", "let's wrap up", "wrap up", "let's finish", "end this session", "let's call it", "that's enough for today", "/break", "taking a break", "back in a bit", or similar.
---

# Finish Session

Runs the end-of-session checklist from CLAUDE.md. Ensures every session ends cleanly with the handoff state captured for next time.

**Mid-session break (`/break`)?** Run steps 0, 1 (progress note only — no handover prompt needed), and 8 (commit anything worth saving). Skip everything else. Cancel the session cron timer if one is running (`CronDelete <job-id>`) — `/start` will set a fresh one on return.

---

## Steps

### 0 — Get the current time

Run `date` to get the actual current time before doing anything else. Use this to:
- Label the session note with the canonical heading format: `## YYYY-MM-DD HH:MM | branch-name`
- Check whether the session is running past 7PM — if so, flag it
- Confirm the correct date for all file edits

---

### 1 — Update the session note

At the top of `SESSION.md`, update (or create) the `## YYYY-MM-DD HH:MM | branch-name` block for today:

- What was built or fixed
- Key decisions made and the reasoning
- Anything discovered that changed the plan
- **Decisions for next session** — the 2–3 most important things to pick up, in priority order
- **Handover prompt** — a self-contained paragraph (or short block) the next Claude session can read cold and immediately understand what was just done and what to pick up next. Written in second person ("PR #X merged. X replaces Y…"). Include: what shipped, any gotchas/debt left behind, and the next priorities in order. Put this in a `> blockquote` after the session note body, labelled `**Handover prompt for next session:**`. This is the single most important thing to get right — it's what turns a session note into a live handoff.

Keep it factual and concise. This is the primary handoff mechanism — the next session starts by reading it.

Do **not** write to `docs/session_log.md` during `/finish`. Session notes are archived to session_log.md at PR merge time (see step 6).

---

### 2 — Move completed items to DONE.md

Scan `ROADMAP.md` for any `- [x]` items (or items completed this session). Move them to the top of `DONE.md` under today's date heading. Remove them from `ROADMAP.md`.

---

### 3 — Add new items

Anything discovered during the session that needs doing:
- New task for the active sprint → add to `ROADMAP.md` **Now**
- Agreed next priority → add to `ROADMAP.md` **Next**
- Backlog idea / later item → add to `ROADMAP.md` **Later** (or `BACKLOG.md` if detailed)
- Session note bullet → add to `SESSION.md` current session note

Don't leave it to memory.

---

### 4 — Update roadmap horizons

In `ROADMAP.md`:
- If a **Next** item was started this session, move it to **Now**
- If priorities shifted, reorder accordingly
- If a **Later** item is now ready to start, check it has a spec in `docs/specs/` before moving to **Next**

---

### 5 — Update CLAUDE.md

If anything changed — new script, renamed column, updated workflow, new skill, schema change — update the relevant section of `CLAUDE.md` in this session. Future sessions start by reading it; stale docs are worse than no docs.

---

### 6 — Archive to session_log.md (if merging now)

If this `/finish` is happening immediately before merging a PR to main, append the session notes to `docs/session_log.md` and reset SESSION.md:

1. Append the current SESSION.md notes to the bottom of `docs/session_log.md`. Heading format: `## YYYY-MM-DD HH:MM | branch-name` (short timestamp — date + time, no seconds).
2. Run `git checkout main -- SESSION.md` to reset SESSION.md to the main branch version.
3. Commit both files together: `"Archive session notes: branch-name"`.

Skip this step if the PR is not being merged this session — the notes stay in SESSION.md on the branch until merge.

---

### 7 — Update open PR TODO checklists

Check for any open PRs on the current branch or any feature branches worked on this session:

```bash
gh pr list --state open
```

For each open PR, review what's left to do and add any remaining TODOs as a checklist at the bottom of the PR description under a `## TODO before merge` heading. This makes the PR a live tracker of what's left, so the next session picks up exactly where things left off.

---

### 8 — Check dirty state and propose commits

```bash
git status
git diff --stat
```

Survey all uncommitted changes. Propose a grouping to the user — one commit per logical feature or change. Wait for approval before staging or committing.

Commit message format:
- First line: short imperative summary (< 72 chars)
- Body: why the change was made, not just what
- End with `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`

---

### 9 — Final check

Once commits are done:

```bash
git status
```

Tree should be clean. If not, flag any remaining uncommitted files and ask whether to commit, stash, or leave.

Confirm push if not already done.

---

## Sign-off

End with a one-line summary of the session:

> "Done. Today: [what shipped]. Next session: [top priority]."
