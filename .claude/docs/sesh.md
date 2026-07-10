# sesh — session timer reference

> **Never guess how far into a session you are — read `sesh status --json`.** `sesh`
> exists because an agent kept misjudging elapsed time (claiming "35 minutes in" ten
> minutes after a 9AM start). It is the *authoritative, on-disk clock* for the working
> session: `now`, `elapsed`, `remaining`, and a `phase` that crosses
> `running → ending_soon → finished`. Any time you need to reason about how long is left,
> whether a hard stop is close, or whether it's past the 7PM cut-off, **read the timer —
> don't estimate from memory of when the session started.**

`sesh` is a *pull*: it never wakes you, you read it when awake. The CronCreate heartbeat
set by `/start` is the *push* that re-invokes the agent every 30 minutes. They are
complementary — the heartbeat forces a check-in; `sesh` tells you the real time when you
check. `sesh` also fires a human-facing macOS banner shortly before the end (see Alerts).

## Commands

```bash
sesh start          # start a 1h session (id inferred from the git worktree root)
sesh start 30m      # 30-minute session
sesh start 90m --lead 10m   # warn 10 minutes before the end (default lead 5m)
sesh status         # human-readable
sesh status --json  # machine-readable — the field an agent should read
sesh pause          # freeze the clock; remaining stops counting down, alert dropped
sesh resume         # unfreeze; end slides later by the paused duration, alert re-armed
sesh restart 45m    # reset the clock to a full duration, same session id
sesh stop           # delete the session state and remove its launchd alert
```

- A **bare number** is minutes: `sesh start 30` → 30m.
- `--lead <duration>` — how long before the end to warn (default `5m`). If a session is no
  longer than its lead, the alert fires immediately.
- When no session is active, `sesh status --json` prints `{"active":false}` (exit 0).

## Session id — one timer per worktree

The id defaults to `sesh-<dir>-<hash>`, inferred from the **session root**: inside a git
repo that is the current working tree's root (the main checkout *or* a linked worktree), so
every subfolder of a worktree shares one timer and separate worktrees get separate ones;
outside a repo it is the working directory. This means each `gwt` worktree carries its own
independent session timer. Override with `--id <id>` or the `SESH_ID` environment variable.

## Status JSON — fields an agent reads

```json
{
  "id": "sesh-sesh-1a2b3c4d",
  "now": "2026-07-10T09:10:00+01:00",
  "start_time": "2026-07-10T09:00:00+01:00",
  "end_time": "2026-07-10T10:00:00+01:00",
  "duration": "1h",
  "elapsed": "10m",      "elapsed_sec": 600,
  "remaining": "50m",    "remaining_sec": 3000,
  "paused": false,
  "finished": false,
  "ending_soon": false,
  "alerted": false,
  "phase": "running"
}
```

- **`phase`** is the field to branch on: `running` → `ending_soon` (within the lead window)
  → `finished` (past the end). Prefer it over recomputing from timestamps.
- **`alerted`** flips to `true` once the launchd warning has fired — the agent-visible half
  of the end alert. A heads-down agent won't see it until it polls, which is why the cron
  heartbeat still matters.
- **`remaining_sec` / `elapsed_sec`** are integers for arithmetic; the string forms are for
  display.

## How it works

- **State** lives in one JSON file per session under `~/.local/state/sesh/` (honouring
  `$XDG_STATE_HOME`), stored as seconds and RFC3339 timestamps so it stays readable and
  hand-editable.
- **Alerts** are scheduled as a per-session `launchd` agent
  (`~/Library/LaunchAgents/com.sesh.<id>.plist`) that runs `sesh _alert <id>` at
  *end − lead*, then unloads itself. It shows a native macOS notification banner (for the
  human) and flips `alerted` + appends to an alert log (surfaced by `sesh status`, for the
  agent). Because `launchd` runs jobs with a clean environment, the plist pins
  `XDG_STATE_HOME` so the fired alert resolves the same state dir the timer started from.
- **Pausing** removes the alert (the wall-clock end has moved) and resuming re-arms it, so
  the warning always tracks the real finish time.

## Skills that call sesh

- **`/start`** — `sesh start <duration> --lead 5m` alongside the cron heartbeat; the
  heartbeat prompt tells the agent to read `sesh status --json` rather than guess.
- **`/save`** — `sesh pause` when stepping away; `sesh resume` on return.
- **`/stop`** — `sesh stop` alongside cancelling the cron timer.

## Install

`go install .` from the `sesh` repo (installs onto `GOBIN`, else `~/go/bin`), or `just
install`. Requires Go 1.26+ and macOS (the alert uses `launchd` + `osascript`). No external
dependencies.
