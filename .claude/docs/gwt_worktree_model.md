# Worktree handling: Claude Code CLI vs `gwt`

Reference for how the Claude Code CLI manages `.claude/worktrees/`, and the
contract `gwt` (`bin/gwt-helper`) follows to stay consistent with it.

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

- **Enumeration** (`ls`, `cp`, `status`, and `cd`/`path`/`zed` resolution) comes
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
