# Worktree handling: Claude Code CLI vs `gwt`

Reference for how the Claude Code CLI manages `.claude/worktrees/`, and the
contract `gwt` (`lib/gwt.rb`) follows to stay consistent with it.

## Principle: git is the source of truth

Both tools treat `git worktree` plumbing as authoritative. Neither enumerates by
scanning the `.claude/worktrees/` directory. Two kinds of mismatch can arise, and
neither is a live worktree:

- an **orphan** — a directory git has not registered. Orphans arise when a
  worktree's git registration is torn down (branch deleted, admin entry pruned)
  but its gitignored, copied-in files are left behind.
- a **phantom** — a registration git still lists but whose working directory is
  gone (git flags it `prunable`). It arises when the directory is deleted out
  from under git without `git worktree remove`.

Neither must be listed or operated on as a worktree.

## How the Claude Code CLI does it

### Create
1. Validate the slug: reject `.`, `..`, a `.git` segment, characters outside
   `[A-Za-z0-9._-]`, and over-length names.
2. Deterministic paths: directory is `<repo>/.claude/worktrees/<branch>` with
   `/` → `+`; the worktree branch is `worktree-<branch>` (same encoding).
3. If the path is already a live registered worktree, reuse it (bump mtime).
4. **Orphan self-heal**: if the path exists but its gitdir is gone, it runs
   `git remote`, `git rev-parse --verify --quiet <branch>`, and
   `git rev-list --max-count=1 <branch> --not --remotes`. It **refuses to delete**
   when the branch has unpushed commits or any check errors; only when provably
   safe does it `rm -rf` and log `removed orphaned worktree directory at …`.
5. Resolve the base ref (HEAD / `origin/<default>` with fetch / `pull/<n>/head`).
6. `git worktree add --no-track -B <wtBranch> <path> <base>` (`--no-checkout`
   when sparse). Partial failures are cleaned with `git worktree remove --force`.
7. Post-setup: copy `settings.local.json`, point `core.hooksPath` at the main
   repo (husky), symlink configured directories, then copy `.worktreeinclude`.

### `.worktreeinclude` (imperative — NOT a git hook)
The copy runs in CLI code after `git worktree add`, not via a `post-checkout`
hook:
- read `.worktreeinclude`, dropping blanks and `#` comments;
- `git ls-files --others --ignored --exclude-standard --directory` to enumerate
  ignored + untracked entries;
- intersect with the include patterns; copy each file main → worktree, skipping
  symlinks.

(A git `post-checkout` hook could not do this anyway — it has no handle on the
source checkout's ignored files.)

### List
`git -C <root> worktree list --porcelain`, parsed. Transient "premature close"
errors are retried.

### Remove
- Dirty-guard: `git status --porcelain`; if changed files exist and the removal
  isn't an explicit exit/force, abort and keep the worktree.
- `git worktree remove [--force]`, falling back to `rm` if git refuses.

### Stale sweep
Scans `.claude/worktrees`, and for agent-worktree-named entries older than a
cutoff that are not active and provably safe, removes them and runs
`git worktree prune`.

## How `gwt` aligns

- **Enumeration** (`ls`, `sync`, `status`, and `cd`/`path`/`zed` resolution) comes
  from `git worktree list --porcelain` filtered to `.claude/worktrees/`, not a
  directory scan. Neither orphans nor phantoms (`prunable` entries) appear.
- **`add`** reuses a registered worktree; if a same-named *unregistered* directory
  is present, it errors and points at `gwt prune` rather than `cd`-ing into a stub.
- **`.worktreeinclude`** copying is imperative, mirroring the CLI: the copy set is
  the intersection of "ignored & untracked" with the include patterns, symlinks
  dereferenced.
- **`rm`** removes a registered worktree via `git worktree remove` (inheriting
  git's dirty-guard; `gwt rm -f` passes `--force`); a stray directory is `rm -rf`'d
  (its branch ref, if any, is independent and untouched).
- **`prune`** clears phantom registrations with `git worktree prune` and removes
  orphaned directories under `.claude/worktrees/` (the latter after confirmation).

## Command surface

| Command | Purpose |
| --- | --- |
| `add [-b] <branch>` | Create a worktree (`-b` also creates the branch) and `cd` in; reuse + `cd` if it already exists |
| `sync [<name>\|--all] [-f] [--hooks]` | Re-merge root's `.worktreeinclude` into a worktree (named, `--all`, or the current one): add missing + refresh stale, never delete; `-f` makes root win on a conflict, `--hooks` re-runs `post-add` |
| `cd <name>` | `cd` into a worktree |
| `zed [<name>]` | Open a worktree in a new Zed window (current if no name) |
| `ls` | List worktrees (name + branch) |
| `rm [-f\|--force] <name>` | Remove a worktree or orphaned directory (`-f` forces a dirty one) |
| `prune [-f]` | Clear phantom git registrations and orphaned directories (`-f` skips prompts) |
| `root [-p]` | `cd` to the main root (or echo it with `-p`) |
| `status` | Per-worktree branch, dirty flag, last-commit time |
| `path [<name>]` | Echo a worktree's absolute path (current if no name) |

## Design decisions

These are deliberate and should be preserved unless revisited on purpose:

- **Fuzzy for navigation, exact for destruction.** `cd`/`path`/`zed` resolve a
  query by exact → prefix → substring match; `rm` requires the exact worktree
  name. Navigation is forgiving; deletion is not fuzzy-matched.
- **Defer to git's guards rather than reimplement them.** `rm` runs
  `git worktree remove` without `--force`, so git's own dirty/locked guard
  decides; `gwt rm -f` forwards `--force`. gwt does not re-derive "is it safe to
  delete".
- **Never auto-delete what git doesn't register.** A directory in the way of
  `add` is reported and the user is pointed at `gwt prune`, not silently removed
  (the CLI's automatic orphan self-heal is deliberately not replicated — pruning
  is an explicit, confirmed action here).
- **stdout is data, stderr is messages.** `path` and `root -p` print only the
  path on stdout so they compose in scripts; errors and prompts go to stderr.
- **`-f` is the force flag, but its meaning is per-command.** `rm`/`prune` take
  `-f` to skip a confirm (and `rm` also forwards git's `--force`); `sync` takes
  `-f`/`--force` to mean "root wins on a conflicting file" (it has no prompt to
  skip). Navigation flags (`add -b`, `root -p`) stay short too.
- **Validate the slug before touching git.** `add` rejects a malformed branch
  name (over 64 chars, `.`/`..`/`.git`/empty segments, non-`[A-Za-z0-9._-]`)
  up front, mirroring the CLI, rather than letting a half-made dir/branch escape.

## Known gaps / deferred

Consciously left out for now (recorded so they are choices, not oversights):

- `zed` hardcodes one editor rather than honouring `$VISUAL`/`$EDITOR`.
- No `move`/`lock`/`unlock`/`repair` equivalents from `git worktree`.
- `sync` only flows root → worktree (canonical → derived). The reverse —
  promoting a worktree's own gitignored file up to root, or shuttling scratch
  laterally between worktrees — is deliberately deferred to a separate,
  explicitly-directional command rather than a `sync --to-root` flag (a
  bidirectional verb, especially with `--all`, is a clobber footgun).
- `status` shows each worktree's last-commit time and dirty flag, but no
  ahead/behind divergence — dropped so the listing stays a pure ref read that
  scales flat with branch count.

## Parity with the Claude Code CLI (2.1.186)

Verified against the CLI's worktree subsystem reverse-engineered from the binary.
The CLI is a superset: it manages *agent* worktrees (locking, base-ref/PR/sparse
resolution, settings/hooks propagation, automatic age-gated cleanup). gwt is a
human tool for feature-branch worktrees, so much of that is out of scope by
design. Where they overlap, gwt matches; where they differ, it is deliberate.

**Matched.** Enumeration from `git worktree list --porcelain`, parsing the
`branch` and `prunable` lines; `/` → `+` directory encoding; a dirty worktree is
never silently removed (the CLI checks `status --porcelain` then force-removes;
gwt withholds `--force` so git's own guard refuses — same outcome); `git worktree
prune` clears phantom/`prunable` registrations; `.worktreeinclude` copies the
intersection of ignored-and-untracked with the include patterns; `prunable`
entries are kept out of the live set (the CLI's enter-guard refuses them).

**Intentionally diverged.**
- gwt names the worktree branch the *actual* branch; the CLI prefixes
  `worktree-` (its branches are throwaway agent branches). Correspondingly gwt
  **never deletes a branch** on `rm`; the CLI runs `branch -D` on its agent
  branch.
- gwt branches from the current `HEAD`; the CLI resolves a base ref
  (`origin/<default>` with fetch, or `pull/<n>/head`) and uses
  `worktree add --no-track -B`.
- gwt does not lock worktrees, nor copy `settings.local.json` / set
  `core.hooksPath` / symlink configured dirs — `gwt sync` re-merges the
  `.worktreeinclude` set into an existing worktree instead (add/refresh, never
  delete; `-f` makes root win, `--hooks` re-runs `post-add`).
- `prune` is manual and per-directory confirmed rather than automatic and
  safety-gated. This is **safe precisely because gwt never deletes branches**:
  an orphan/stray directory holds only gitignored leftovers (a real worktree
  with commits would still be registered), and any commits live on the branch in
  `.git`, not in the directory — so removing the directory cannot lose committed
  work. The CLI's elaborate "provably safe / unpushed-commits" self-heal exists
  because it *also* deletes the branch; gwt sidesteps that whole class of risk.
- `.worktreeinclude`: gwt dereferences symlinks (`cp -RL`) to seed a real file
  (e.g. a symlinked `CLAUDE.local.md`); the CLI skips symlinks. gwt's choice is
  the more useful one for this setup.

**Adopted from the CLI.**
- Slug validation: `add` mirrors `validateWorktreeSlug` (64-char cap, reject
  `.`/`..`/`.git`/empty segments and non-`[A-Za-z0-9._-]` per `/`-segment) before
  touching git.
- The `worktree list` capture is bounded by a 10s timeout and retried once on a
  transient failure (the CLI's `WorktreeGitTransientError` handling; in Ruby's
  blocking-read model the retry covers the same one-off failures).
