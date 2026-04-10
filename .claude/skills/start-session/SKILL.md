---
name: start-session
description: Run the session start routine — ask about available time and hard stops, read SESSION.md session note and ROADMAP.md Now priorities, propose a realistic goal for the session. Use when the user says "/start", "/start-session", "let's start", "start session", "begin session", or at the start of any longer session. Skip for quick focused tasks where the goal is already clear.
---

# Start Session

Runs the session start routine documented in CLAUDE.md. Ensures every session begins with a shared understanding of available time, current priorities, and a single concrete goal.

---

## Steps

### 0 — Get the current time and check for stale sessions

Run `date` to get the actual current time before doing anything else. Use this to:
- Confirm the correct date for session note labelling
- Accurately compute cron expressions for hard stop warnings and break reminders
- Check whether the session start is already past 7PM

Then check whether the previous session ended cleanly by comparing `SESSION.md` mtime against the most recent JSONL transcript:

```bash
PROJECT_DIR="$HOME/.claude/projects/$(pwd | sed 's|/|-|g')"
LATEST_JSONL=$(ls -t "$PROJECT_DIR"/*.jsonl 2>/dev/null | head -1)
if [ -n "$LATEST_JSONL" ] && [ -f "SESSION.md" ]; then
  JSONL_MTIME=$(stat -f "%m" "$LATEST_JSONL")
  SESSION_MTIME=$(stat -f "%m" "SESSION.md")
  if [ "$JSONL_MTIME" -gt "$SESSION_MTIME" ]; then
    echo "⚠️  SESSION.md is older than the last session transcript — previous session may not have run /finish"
  fi
fi
```

If the check fires, tell the user:

> "It looks like the last session didn't run `/finish` — SESSION.md is older than the most recent transcript. Want me to run `/recover` to reconstruct what happened, or skip and continue from the current SESSION.md?"

Wait for their answer. If they say recover, invoke `/recover` before continuing with step 1.

---

### 1 — Ask the two questions

Before reading anything, ask:

> "How much time do we have today, and any hard stops during the session?"

Wait for the answer. Use it to calibrate everything that follows — a 30-minute session gets one small task, a 2-hour session can tackle the next sprint item.

**If the user mentions a hard stop at a specific time** (e.g. "lunch at 1pm", "run at 2:30"), schedule a one-shot warning 15 minutes before using CronCreate:

- `cron`: derived from the stop time minus 15 minutes (e.g. stop at 13:00 → `45 12 * * *`)
- `prompt`: `⚠️ Hard stop in ~15 mins — time to reach a clean stopping point and run /finish.`
- `recurring`: `false`

Report the job ID so it can be cancelled if plans change.

---

### 2 — Archive session notes (direct-to-main only)

`docs/session_log.md` is append-only — entries are added at the bottom when a PR merges. Feature branches handle their own archiving at merge time.

**Only do this step if the previous session was on `main` directly** (i.e. no PR involved):

1. Read `SESSION.md` and locate the most recent session note block.
2. Check whether `docs/session_log.md` already has an entry for that date + branch — if so, skip.
3. Append the session note to the bottom of `docs/session_log.md` with the heading `## YYYY-MM-DD HH:MM | main`.
4. In `SESSION.md`, delete all but the most recent session note to keep the file lean.

Skip entirely if the previous session was on a feature branch — that branch's notes will be appended when the PR merges.

---

### 3 — Read the current state

Read these files:

```
SESSION.md     — latest session note + Decisions for next session
ROADMAP.md     — Now / Next / Later priorities
```

Extract:
- The **Handover prompt** from the latest session note in `SESSION.md` — read this first. It's a self-contained paragraph written by the previous session specifically for you. Surface it verbatim (or a tight summary) before proposing a goal, so the user knows you've picked up exactly where things left off.
- The **Now** priorities from `ROADMAP.md`
- The **Next** items and which is first in line
- The **Decisions for next session** from the latest session note in `SESSION.md`
- Any open items from the previous session that weren't completed

Run `gh pr list --state open --json number,headRefName,labels,createdAt,isDraft | jq -r '.[] | "\(.number) | \(.headRefName) | \(.labels | map(.name) | join(", ")) | \(if .isDraft then "draft" else "open" end) | \(.createdAt[:10])"' | sort -t'|' -k1 -n` and display the results as a table (PR | Branch | Label | Status | Created). This gives a quick overview of in-flight work before proposing the session goal.

---

### 4 — Check open PRs

```bash
gh pr list --state open
```

For each open PR, check if it has a `## TODO before merge` checklist in the description. If so, surface the outstanding items to the user — these are likely the first things to pick up this session.

---

### 5 — Propose a goal

Based on available time and the roadmap, propose **one concrete thing to finish** — not a wish list.

Format:

> "Given [X time], I'd suggest we tackle **[specific task]** today — [one sentence on why it's the right pick: it's next on the roadmap / it's a blocker / it's a quick win that clears the way]. That should be completable in [Y time] leaving [Z buffer].
>
> Anything you want to adjust, or shall we go?"

Rules:
- One goal. Not two, not "we could also...".
- If the top Next item is too large for the available time, scope it down to a deliverable sub-task, or suggest a smaller quick win instead and flag that the big item needs a dedicated session.
- If there's a hard stop mid-session, flag it now: "We'll hit your [time] stop about halfway through — we should aim to reach a clean stopping point by then."

---

### 6 — Set the pacing

**If the session is 30 minutes or shorter:** schedule a one-shot end warning instead of a recurring check-in — fire ~5 minutes before the end of the stated session duration:

- `cron`: current time + (duration - 5 minutes), pinned to today's date
- `prompt`: `⚠️ Session almost up — time to reach a clean stopping point and run /finish.`
- `recurring`: `false`

**If the session is longer than 30 minutes:** schedule a recurring 30-minute check-in:

- `cron`: `*/30 * * * *`
- `prompt`: `30-minute check-in — how's progress? On track for the session goal? Any hard stop coming up? Also a good moment for a 5-min break if needed.`
- `recurring`: `true`

Confirm to the user that the timer is set, and note the job ID so it can be cancelled with CronDelete if plans change. Recurring cron jobs auto-expire after 3 days.

If the session is running past **7PM**, say so directly:

> "It's past 7PM — want to wrap up and pick this up next session?"

---

## Wrapping up

When the user signals they're done or approaching a hard stop, prompt:

> "Ready to wrap up? Run `/finish` and I'll take you through the end-of-session checklist."
