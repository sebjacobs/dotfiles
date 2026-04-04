---
name: break-session
description: Save mid-session state before a break. Use when the user says "/break", "taking a break", "let's take a break", "back in a bit", "stepping away", "pausing", or similar.
---

# Break Session

Run `finish-session` in quick mode: steps 0, 1 (progress note only — no handover prompt), and 8 (commit anything worth saving). Skip steps 2–7.

Also cancel the session cron timer if one is running (`CronDelete <job-id>`) — `/start` will set a fresh one on return.
