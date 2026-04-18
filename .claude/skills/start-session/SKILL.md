---
name: start-session
description: Run the session start routine — ask about available time and hard stops, read recent session logs and ROADMAP.md priorities, propose a realistic goal. Use when the user says "/start", "/start-session", "let's start", "start session", "begin session", "continue session", or at the start of any longer session. Skip for quick focused tasks where the goal is already clear.
---

# Start Session

Runs the session start routine documented in CLAUDE.md. Ensures every session begins with a shared understanding of available time, current priorities, and a single concrete goal.

---

## Steps

### 0 — Get the current time and check for incomplete sessions

Run `date` to get the actual current time before doing anything else. Use this to:
- Confirm the correct date for session note labelling
- Accurately compute cron expressions for hard stop warnings and break reminders
- Check whether the session start is already past 7PM

Determine the project name and branch:

```bash
basename "$(git rev-parse --show-toplevel)"
git rev-parse --abbrev-ref HEAD
```

Then check whether the previous session ended cleanly:

```bash
jotter tail --project <project> --branch <branch> --limit 1
```

If the last entry is **not** a `finish` type (i.e. it's a `start`, `checkpoint`, or `break`), the previous session likely crashed or the user forgot `/finish`. Tell the user:

> "The last session entry is a [type], not a finish — the previous session may not have run `/finish`. Want me to run `/recover` to reconstruct what happened, or skip and continue?"

Wait for their answer. If they say recover, invoke `/recover` before continuing with step 1.

---

### 1 — Ask the two questions

Before reading anything else, ask:

> "How much time do we have today, and any hard stops during the session? Or already have a goal in mind?"

Wait for the answer. Use it to calibrate everything that follows — a 30-minute session gets one small task, a 2-hour session can tackle the next sprint item.

If the user already has a goal in mind, skip the time-budget calibration and cron pacing — go straight to step 2 for context restoration, then work toward their stated goal.

**If the user mentions a hard stop at a specific time** (e.g. "lunch at 1pm", "run at 2:30"), schedule a one-shot warning 15 minutes before using CronCreate:

- `cron`: derived from the stop time minus 15 minutes (e.g. stop at 13:00 → `45 12 * * *`)
- `prompt`: `Hard stop in ~15 mins — time to reach a clean stopping point and run /finish.`
- `recurring`: `false`

Report the job ID so it can be cancelled if plans change.

---

### 2 — Restore context from session logs

First check which branches have logs — cheaper than letting `tail` error when nothing exists:

```bash
jotter ls --project <project>
```

If the current branch has a log, read its last few entries:

```bash
jotter tail --project <project> --branch <branch> --limit 5
```

If the current branch isn't in `jotter ls` but `main` is, fall back to that for broader project context:

```bash
jotter tail --project <project> --branch main --limit 3
```

If neither exists, skip straight to step 3 — no prior context to restore.

Surface the most recent finish entry's `**Next:**` field — that's the handover from last session. Present it verbatim (or a tight summary) before proposing a goal, so the user knows you've picked up exactly where things left off.

---

### 3 — Read the roadmap

```
ROADMAP.md     — Now / Next / Later priorities
```

Extract:
- The **Now** priorities
- The first **Next** item in line
- Any open items from the previous session that weren't completed

---

### 4 — Check open PRs

```bash
gh pr list --state open --json number,headRefName,labels,createdAt,isDraft | jq -r '.[] | "\(.number) | \(.headRefName) | \(.labels | map(.name) | join(", ")) | \(if .isDraft then "draft" else "open" end) | \(.createdAt[:10])"' | sort -t'|' -k1 -n
```

Display as a table (PR | Branch | Label | Status | Created). For each open PR, check if it has a `## TODO before merge` checklist in the description. If so, surface the outstanding items — these are likely the first things to pick up this session.

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
- `prompt`: `Session almost up — time to reach a clean stopping point and run /finish.`
- `recurring`: `false`

**If the session is longer than 30 minutes:** schedule a recurring 30-minute check-in:

- `cron`: `*/30 * * * *`
- `prompt`: `30-minute check-in — how's progress? On track for the session goal? Any hard stop coming up? Also a good moment for a 5-min break if needed.`
- `recurring`: `true`

Confirm to the user that the timer is set, and note the job ID so it can be cancelled with CronDelete if plans change. Recurring cron jobs auto-expire after 3 days.

If the session is running past **7PM**, say so directly:

> "It's past 7PM — want to wrap up and pick this up next session?"

---

### 7 — Write the start entry

```bash
jotter write \
  --project <project> \
  --branch <branch> \
  --type start \
  --content "<session goal, available time, approach>"
```

---

## Wrapping up

When the user signals they're done or approaching a hard stop, prompt:

> "Ready to wrap up? Run `/finish` and I'll take you through the end-of-session checklist."
