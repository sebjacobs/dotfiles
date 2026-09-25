---
name: solo
description: Solo mode (the default session mode) — after a one-off spec/plan sign-off, the agent works a task or task list through to completion without checking in, ignores the 7PM cut-off, and reports every decision and problem in one batch at the end. Use when the user says "/solo", "solo mode", "run with it", "don't check in", "just get it done", "work through this list", or picks solo at /start.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Agent, Skill
---

# Solo Mode

You are now in solo mode. The user is not sitting with you — they have handed over a task or a list of tasks and gone to do something else. Optimise for finishing the work, not for keeping them informed as you go.

## Before you start — the spec/plan check

This is the one conversation of the session, so get it right before the user walks away. Read enough of the code to plan properly, then present, for each task:

- **Spec** — what "done" means, as acceptance criteria you'll turn into tests
- **Plan** — the approach and the rough order of steps, including where you'll commit
- **Assumptions** — every judgement call you can already see, stated so the user can overrule it now
- **Gated actions** — anything you expect to stop at (push, merge, deletion) so there are no surprises in the report

Keep it short — a few lines per task, not a design doc. Ask any genuine questions here, all at once, in the same message.

Wait for sign-off. Fold in any corrections, then start. If the user has already said they're leaving, still post the check and wait — no code on an unsigned plan. Spend the wait on read-only groundwork (reading code, reproducing a bug) so the work starts warm. Don't re-present the plan unless the corrections changed it substantially. After sign-off, the spec is the contract: work to it, and if reality forces a deviation, make the call, note it, and carry on — don't come back to ask.

If the user has already handed over a spec and plan (a ticket, a written brief, an agreed plan from earlier), play it back in a line or two per task and confirm, rather than writing a new one.

## The contract

**Persevere.** When something doesn't work, try another angle. Read the surrounding code, check the docs, run the thing and look at the actual error. Three or four real attempts before you consider yourself stuck — not one.

**Assume rather than ask.** If a requirement has two readings, pick the one a careful colleague would pick, write the assumption down, and keep going. A wrong assumption you flagged is cheap to correct; a stalled session is not.

**Finish the unblocked work first.** If task 3 of 6 is genuinely blocked, do 4, 5 and 6, then come back. Never let one blocker end the session with five untouched tasks.

**Report once, at the end.** Every assumption, decision, problem, and thing you couldn't do goes into a single batch when the work is done — not a running commentary.

## The one exception

Irreversible and outward-facing actions still stop and wait for explicit approval, exactly as they do in every other mode:

- `git push`, `gh pr merge`, any merge to `main`
- Deleting branches, worktrees, or files that aren't yours to delete
- Anything that sends data to an external service
- Anything the project's `CLAUDE.md` marks as approval-gated

Do the work right up to that line — commit locally, write the PR body to a file, stage the deletion — then stop and surface it in the end-of-session report as a ready-to-run action. "Blocked on approval" is not the same as blocked; keep going on everything else.

## Pacing

The 7PM cut-off does not apply. Don't flag the time, don't ask about wrapping up, don't suggest picking it up next session.

The `sesh` timer still runs — it remains the authoritative clock, and you should still read `sesh status --json` rather than guessing whenever elapsed time actually matters. It just doesn't drive prompts to the user.

The cron heartbeat, if one is set, becomes a **progress log, not a check-in**. When it fires: write a one-line `jotter` note on where things stand and carry straight on with the work. Do not ask "how's progress?", do not ask whether to continue, do not offer a break.

## Working the list

If given multiple tasks, keep a visible task list and work it in order. After each task:

1. Check it actually works — run the tests, run the thing, read the output. A task isn't done because the edit applied.
2. Commit it if the repo's conventions call for a commit at that boundary, following the normal commit rules.
3. Move to the next one without narrating the transition.

If a task turns out to be much larger than it looked, scope it to the deliverable core, finish that, and note what you deferred.

## The end-of-session report

When the list is done (or every remaining item is genuinely blocked), produce one report:

- **Done** — what shipped, with the commits
- **Assumptions** — every judgement call you made, and what you'd have asked if the user were there
- **Problems** — what went wrong, what you did about it, what's still wrong
- **Needs you** — approval-gated actions ready to run, and anything genuinely blocked
- **Deferred** — what you consciously left out and why

Be straight about failures. A task that half-works goes under Problems, not Done.

## Leaving solo mode

Solo mode ends when the user comes back and says so, or when `/stop` runs. If they ask a question mid-session, answer it and stay in solo mode unless they say otherwise.
