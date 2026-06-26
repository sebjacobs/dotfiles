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
repo and is symlinked into place by `setup.sh` (add the filename to the `files`
array there). Example: `com.sebjacobs.ruby-lsp-reap.plist`.

### 2. per-project

The plist lives in the project repo (e.g. `scripts/launchd/com.sebjacobs.<job>.plist`)
so it's versioned alongside the code it runs. `setup.sh` can't know about these,
so symlink and load them by hand once:

```bash
ln -s "$PWD/scripts/launchd/com.sebjacobs.<job>.plist" ~/Library/LaunchAgents/
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.sebjacobs.<job>.plist
```

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

```bash
launchctl bootout   "gui/$(id -u)/com.sebjacobs.<job>"            # unload by label
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.sebjacobs.<job>.plist
```

If `bootout` fails with an I/O error because the symlink was already removed,
unload by the label target directly: `launchctl bootout "gui/$(id -u)/<label>"`.
