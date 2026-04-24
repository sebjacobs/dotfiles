# Jotter — session logging reference

> **`jotter search` with no search term returns every entry.** Combine with `--project`, `--branch`, `--since`, `--until` to dump a whole project, branch, or date window as full entries — not just counts. This is the fastest way to read back previous sessions in full. Easy to forget because "search" implies a query is required; it isn't.
>
> ```bash
> jotter search --project "$(jotter project)"                       # everything, this project
> jotter search --project "$(jotter project)" --branch main         # everything on main
> jotter search --project "$(jotter project)" --since 2026-04-19    # everything from a date onwards
> jotter search --project "$(jotter project)" --until 2026-04-19    # everything up to a date
> jotter search --project "$(jotter project)" --since 2026-04-15 --until 2026-04-19   # windowed
> ```

Session notes are stored in a private data repo via `jotter`, not in project repos. This eliminates the merge-time cleanup ceremony that SESSION.md required (prefix commits, manual resets, archiving).

## Storage layout

- JSONL entries at `$JOTTER_DATA/logs/<project>/<branch>.jsonl`, one JSON object per line
- Branch names: `/` replaced with `+` in filenames (e.g. `feature+auth.jsonl`)

## Commands

### `jotter write` — append an entry

```bash
jotter write \
  --project "$(jotter project)" \
  --branch "$(jotter branch)" \
  --type <type> \
  --content "Entry body text" \
  --next "What to pick up next"   # optional, used by /start for handover
```

**`--type` values:** `start`, `checkpoint`, `note`, `break`, `finish`

- `finish` also pushes the data repo to remote; all others just commit locally.
- `--next` is optional but recommended on `finish` and `break` — `/start` reads it to restore context.
- `jotter project` and `jotter branch` resolve the current git repo's project name and branch automatically; prefer them over hardcoding.

**Minimal one-liner for an ad-hoc note:**
```bash
jotter write --project "$(jotter project)" --branch "$(jotter branch)" --type note --content "Your note here"
```

### `jotter tail` — read recent entries

```bash
jotter tail --project "$(jotter project)" --branch "$(jotter branch)" --limit 5
```

Defaults to `--limit 1` (most recent entry only).

### `jotter ls` — list projects or branches

```bash
jotter ls                                                        # all projects
jotter ls --project "$(jotter project)"                          # branches in this project
jotter ls --project "$(jotter project)" --branch main            # entries on a branch
jotter ls --project "$(jotter project)" --since 2026-04-19       # filtered by date
```

### `jotter search` — search entries by content

```bash
jotter search --project "$(jotter project)" "keyword"            # search this project
jotter search --project "$(jotter project)"                      # dump all entries (no term needed)
jotter search --project "$(jotter project)" --type finish        # filter by entry type
jotter search --project "$(jotter project)" --since 2026-04-19  --until 2026-04-20 ""
```

Accepts `--project`, `--branch`, `--type`, `--since`, `--until`. Search term is optional — omitting it returns all entries matching the filters.

## `jotter write` — full syntax

```bash
jotter write \
  --project "$(jotter project)" \
  --branch "$(jotter branch)" \
  --type <type> \
  --content "Entry body text" \
  --next "What to pick up next"   # optional, used by /start for handover
```

**`--type` values:** `start`, `checkpoint`, `note`, `break`, `finish`

- `finish` also pushes the data repo to remote; all others just commit locally.
- `--next` is optional but recommended on `finish` and `break` — `/start` reads it to restore context.
- `jotter project` and `jotter branch` resolve the current git repo's project name and branch automatically; prefer them over hardcoding.

**Minimal one-liner for an ad-hoc note:**
```bash
jotter write --project "$(jotter project)" --branch "$(jotter branch)" --type note --content "Your note here"
```

## Git integration

Every `write` auto-commits in the data repo; `--type finish` also pushes to remote.

## Skills that call jotter

`/start`, `/save`, `/finish`, `/break` — no manual session note management needed.

**Context restoration:** `/start` runs `tail --limit 5` to restore context from the last few entries. The most recent finish entry's `**Next:**` field is the handover prompt.

## Retrospective queries — reach for `jotter ls` / `jotter search` first

Both `ls` and `search` accept `--since` and `--until` filters (`YYYY-MM-DD` or `YYYY-MM-DDTHH:MM:SS`, inclusive). Use these to reconstruct what happened over a window before diving into Claude Code's raw transcripts (`~/.claude/projects/*.jsonl`).

- **"What did we do yesterday across this project?"**
  ```bash
  jotter ls --project "$(jotter project)" --since 2026-04-19 --until 2026-04-19
  jotter search --project "$(jotter project)" --since 2026-04-19 --until 2026-04-19 ""
  ```
  `ls` gives branch-level entry counts; `search` with an empty term dumps the entries themselves.

- **Narrow to a time window:** `--since 2026-04-19T14:00:00 --until 2026-04-19T19:00:00`.

- **Find every mention of X in this project:** `jotter search --project "$(jotter project)" "X"` — also accepts `--branch`, `--type`, and the date filters.

Rule of thumb: if the answer is likely in a checkpoint/finish entry, jotter is enough. Only fall back to the Claude Code transcript for moment-to-moment reconstruction (crashed mid-session with no checkpoint, or need the literal conversation).
