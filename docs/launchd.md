# launchd agents (`com.sebjacobs.*`)

How my personal scheduled jobs are wired up, and why `svc ls` only shows some of
them.

## The convention

- **Naming.** Every personal agent uses the label `com.sebjacobs.<job>` and the
  plist is named `com.sebjacobs.<job>.plist`. The `svc` CLI (`bin/svc`) globs
  exactly `~/Library/LaunchAgents/$LAUNCHD_PREFIX.*.plist` (the `LAUNCHD_PREFIX`
  env var, defaulting to `com.sebjacobs`) — anything not following this prefix is
  invisible to it. The prefix is the opt-in contract: any app names its agents
  `$LAUNCHD_PREFIX.<job>` to be managed by `svc`. (Vendor agents like
  `com.google.*` are filtered out on purpose; an agent of mine named `local.*` or
  `battery.plist` simply won't show up.)
- **Location.** launchd only loads plists from `~/Library/LaunchAgents`. The real
  file can live anywhere — in this repo, or in a project repo — but a **symlink**
  must exist in `~/Library/LaunchAgents` pointing at it.
- **The Label inside the plist must match the filename.** `svc` reads the Label;
  launchd keys the loaded service off it. Keep them in sync or you get ghost
  entries.

## Two kinds of agent

### 1. dotfiles-managed (machine-wide)

The plist lives in [`Library/LaunchAgents/`](../Library/LaunchAgents/) in this
repo. `setup.sh` globs every `$LAUNCHD_PREFIX.*.plist` there, symlinks each into
`~/Library/LaunchAgents`, and (re)loads it — so adding an agent is just dropping
its plist into that directory; no edit to `setup.sh` is needed. Example:
`com.sebjacobs.ruby-lsp-reap.plist`.

### 2. per-project

The plist lives in the project repo (e.g. `scripts/launchd/com.sebjacobs.<job>.plist`)
so it's versioned alongside the code it runs. `setup.sh` can't know about these,
so install it once from the project with `svc`:

```bash
svc install scripts/launchd/com.sebjacobs.<job>.plist
```

This symlinks the real file into `~/Library/LaunchAgents` and bootstraps it.

## Common gotchas

- **`svc ls` shows nothing for an agent that exists.** It's almost always the
  naming prefix (not `$LAUNCHD_PREFIX.`) or a missing symlink in
  `~/Library/LaunchAgents`. An agent can be *loaded* in launchd (bootstrapped
  directly from its source path) yet absent from `svc ls` because no symlink lives
  in the scanned directory.
- **No log line in `svc ls`.** `svc` reads `StandardOutPath`. A plist that logs via
  a shell redirect (`exec … >> "$HOME/…log"`) instead of `StandardOutPath` won't
  surface its log — that's expected. The shell-wrapper form is used when the log
  path needs `$HOME` expansion (launchd does not expand `$HOME` in
  `StandardOutPath`, so the alternative is hardcoding an absolute, username-bound
  path).

## Reloading after an edit

`svc edit <job>` opens the plist's real file in `$EDITOR` and reloads it (bootout
+ bootstrap) on exit. To reload a plist you edited some other way:

```bash
svc unload <job> && svc load <job>
```

To run a job immediately regardless of its schedule, `svc restart <job>`
(`kickstart -k`).
