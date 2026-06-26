# `svc` — launchd service management CLI (spec)

A single project-agnostic CLI over my personal launchd agents, replacing the
scattered `jls` + raw `launchctl` workflow. The command is `bin/svc` (Ruby),
symlinked onto `$PATH` by `setup.sh` like every other `bin/` script, so it runs
from any repo. No zsh wrapper — `svc` needs no shell-only behaviour (unlike `gwt`,
whose wrapper exists only to `cd` the interactive shell), so the executable is
`bin/svc` directly rather than a `bin/svc-helper` + wrapper pair.

## The opt-in contract: `LAUNCHD_PREFIX`

The agent prefix moves out of the tool and into an env var defined in
`zsh/env.zsh`:

```bash
export LAUNCHD_PREFIX="com.sebjacobs"
```

`svc` reads it with a fallback (`PREFIX="${LAUNCHD_PREFIX:-com.sebjacobs}"`).
Any app or project opts its agents into `svc` simply by naming them
`$LAUNCHD_PREFIX.<job>` — the prefix is the contract, not hard-coded in the
tool. A single string, not a list: one reverse-DNS prefix is the whole point.

## Command surface

| Command | launchctl underneath | Purpose |
|---|---|---|
| `svc ls` | `print-disabled` + `list` | All agents, summary (absorbs `jls`) |
| `svc show <job>` | same, one agent | Drill into one agent |
| `svc install <plist>` | symlink + `bootstrap` | Opt a plist in (from any project), prefix-validated |
| `svc edit <job>` | resolve link → `$EDITOR` → reload | Edit the real file + auto-reload |
| `svc enable\|disable <job>` | `enable` / `disable` | Persistent allow-flag (turns schedule on/off) |
| `svc load\|unload <job>` | `bootstrap` / `bootout` | Register/unregister in current session |
| `svc restart <job>` | `kickstart -k` | Run / re-run the job now |
| `svc tail <job>` | `tail -f` on log path | Follow the log |

### Semantics that drove the verb split

`enable` ≠ `start`. They are orthogonal:

- **enable / disable** — a *persistent* allow-flag in launchd's database. A
  disabled agent refuses to load on login/bootstrap and stays that way across
  reboots (the `DISABLED` state `jls` reads via `print-disabled`). For a
  scheduled job, `disable` turns the **schedule** off.
- **load / unload** (`bootstrap` / `bootout`) — register/unregister with the
  *current* session: "is it loaded right now."
- **restart** (`kickstart -k`) — actually *run the job now*, regardless of
  schedule. The common need after editing a plist.

## `svc install` — works from any project

Automates the manual per-project two-liner currently in `docs/launchd.md`:

```bash
svc install scripts/launchd/com.sebjacobs.foo.plist
```

- Symlinks the **real (absolute, `$PWD`-resolved) project file** into
  `~/Library/LaunchAgents`, so edits in the project repo stay live and the
  project keeps owning its plist.
- `bootstrap`s it into launchd (closing the gap where `setup.sh` symlinks but
  never loads).
- **Validates the prefix**: refuses (or warns on) a plist not named
  `$LAUNCHD_PREFIX.*`, keeping stray agents out of the managed set.

## `svc edit` — edit the source, then reload

- Resolve the `~/Library/LaunchAgents` symlink to its target so `$EDITOR` opens
  the source-of-truth file (in the repo/project), not the link.
- After editing, reload (`bootout` + `bootstrap`) so the change takes effect —
  the gotcha documented in `docs/launchd.md`.

## Build order (incremental, each its own commit)

1. ✅ `LAUNCHD_PREFIX` env var in `zsh/env.zsh`.
2. ✅ `bin/svc` (Ruby, `gwt-helper` shape) + `svc ls` with `svc_test.rb`; `jls`
   deleted (output is byte-identical), docs repointed at `svc`.
3. ✅ `svc tail` (resolve job → follow its `StandardOutPath`) and `svc show`
   (one agent's plist path, schedule, state, program, log). Added the shared
   fuzzy job-resolver (short name or full label) that `enable`/`restart` reuse.
4. ✅ `svc install` (symlink the real file + bootstrap, prefix-validated,
   idempotent, refuses to clobber a foreign link).
5. ✅ `svc edit` (resolve link → `$EDITOR` → bootout + bootstrap reload).
6. ✅ `svc enable|disable|load|unload|restart` (launchctl pass-throughs over a
   shared resolve-act-report helper).
7. ✅ Rewired `setup.sh` to glob `Library/LaunchAgents/$PREFIX.*.plist`,
   symlinking and bootstrapping each (closes the load-gap, prefix-aware instead
   of naming files). Done in sh, not `svc install`, because setup runs before a
   modern Ruby is guaranteed. `docs/launchd.md` now points at `svc install` /
   `svc edit` instead of the manual launchctl snippets.

## Technology & testing

**Ruby + minitest, mirroring `bin/gwt-helper`** (in `bin/svc`, tests in
`test/bin/svc_test.rb`). The repo already has the pattern and harness, and
`svc` is an ideal fit:

- **Pure logic as module functions** (like `Gwt.parse_worktrees`,
  `Gwt.fuzzy_match`) — `svc`'s schedule parsing (`StartCalendarInterval` /
  `StartInterval` → display string), `$LAUNCHD_PREFIX` validation, and
  `ls`/`show` formatting are all pure and the most bug-prone bits. Tested with
  zero side-effects.
- **Injectable seams for side-effects** — `gwt` injects `Git` and `System` into
  `App.new(git:, sys:, ...)`. `svc` gets a `Launchctl` seam (`list`,
  `print-disabled`, `bootstrap`, `bootout`, `enable`, `kickstart`) plus `System`
  (symlink, readlink, exist?). Tests inject a `FakeLaunchctl` so no real agents
  are touched.
- **Harness already exists** — `.claude/scripts/test_helper.rb`'s `load_script`
  + the `__FILE__ == $PROGRAM_NAME` guard. Tests live in
  `test/bin/svc_test.rb` alongside `gwt_helper_test.rb`. Run on
  `ruby-4.0.5`.
</content>
</invoke>
