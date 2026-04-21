# Git practices

Reference material underpinning the git conventions in `CLAUDE.md`. Two sections: the original FutureLearn engineering post on commit hygiene, and a branch triage runbook for cleaning up mixed-concern branches.

---

## Telling stories with your Git history

*Published March 26th, 2015 by Seb Jacobs — FutureLearn engineering blog*

Our Git history is a living, ever-changing, searchable record that tells the story of how and why our code is the way it is.

### 1. Atomic commits

Think of atomic commits as the smallest amount of code changed which delivers value. Apply the **Single Responsibility Principle** to commits — a commit should have exactly one reason to change. If you can describe a commit with "and", it's doing too much. Ask yourself: if this change needed to be reverted, would you want to undo all of it together, or just one part?

### 2. Useful commit messages

If there's one thing to remember, it is to explain why you've made the change in the first place. Look at the commit from the perspective of another developer. What questions might they be asking? What might not be immediately obvious?

```
Short one line title.

An explanation of the problem, providing context.

Longer description of what the change does.

An explanation of why the change is being made.

Perhaps a discussion of alternatives that were considered.
```

The first line should explain the *value* of the changes, not the implementation details.

### 3. Revise history before sharing

You shouldn't think of your Git history as a "truthful" log of what you worked on step-by-step. Just as we refactor code, we should refactor our commits before sharing them. Squash fixup commits, reorder for clarity, remove noise.

### 4. Single purpose branches

Think carefully about the purpose and scope of your feature branch. Changes that provide a clear benefit unrelated to the feature can be landed on main separately — and earlier. Splitting up branches reduces merge pain and delivers value sooner.

### 5. Keep your history linear

Rebase feature branches before merging. This groups related commits together while keeping merges clean, making it easier to identify when a particular change was introduced.

---

## Branch triage — cleaning up branches with mixed changes

Long-running feature branches often accumulate changes that don't all belong together. Before raising PRs, triage what's there and separate the concerns.

**The key driver is unblocking.** Fixes and docs that land on main become the shared base for all other branches. The merge order matters: low-risk, independent changes first — then larger features on top of a clean foundation.

### When to do this

- Multiple feature branches haven't been merged for a while
- Some commits are clearly fixes or housekeeping with no dependency on the feature
- A yak shave produced something independently useful that shouldn't wait for the feature
- Other branches are blocked on changes buried inside a larger feature branch

### Step 1 — survey the branches

```bash
for branch in feature/foo feature/bar; do
  echo "=== $branch ==="
  git log main...$branch --oneline
done
```

Sort commits into buckets: **Fixes / correctness**, **Infrastructure / housekeeping**, **Research / documentation**, **New features**.

### Step 2 — create focused branches from main

```bash
git checkout main
git checkout -b feature/fixes
git checkout -b feature/docs
```

### Step 3 — cherry-pick the right commits onto each branch

```bash
git checkout feature/fixes
git cherry-pick <sha1> <sha2> <sha3>
```

Cherry-pick in chronological order. For session note conflicts (`SESSION.md`, `docs/session_log.md`), take `ours` — the current branch has the most recent note:

```bash
git cherry-pick -X ours <sha1> <sha2> <sha3>
```

### Step 4 — rebase the original feature branches onto the new base

```bash
git checkout feature/my-feature
git rebase -X ours feature/fixes
```

Git automatically skips commits already upstream (recognised by patch content). `warning: skipped previously applied commit` is expected.

### Step 5 — verify

```bash
for branch in feature/fixes feature/foo feature/bar; do
  echo "=== $branch ==="
  git log feature/fixes..$branch --oneline
done
```

Each branch should show only the commits that genuinely belong to it.

### Step 6 — raise PRs and force-push

```bash
git push -u origin feature/fixes
gh pr create ...

# After adding commits to an existing branch:
git push --force-with-lease origin feature/fixes
```

Once `feature/fixes` merges to main, rebase all remaining branches:

```bash
git checkout feature/my-feature
git rebase main
git push --force-with-lease origin feature/my-feature
```

### Tips

- **`-X ours` for session notes** — `SESSION.md` and `docs/session_log.md` conflict constantly. Taking `ours` is almost always correct.
- **Empty commits** — if all changes were already in HEAD, use `git cherry-pick --skip`.
- **Hollow branches** — after triage, some branches may only have session notes left. Delete once the focused branch merges.

### Squashing without interactive rebase

When interactive rebase isn't available, rebuild using `cherry-pick --no-commit`:

```bash
git checkout -b feature/<name>-clean origin/main
git cherry-pick <sha>                          # individual commits
git cherry-pick --no-commit <sha1> <sha2>      # squash group
git commit -m "..."
git push origin feature/<name>-clean:feature/<name> --force
git checkout feature/<name> && git reset --hard origin/feature/<name>
git branch -D feature/<name>-clean
```

**Conflict handling during `--no-commit` picks:** if a pick conflicts, do **not** run `git cherry-pick --continue` — that finalises the pick as its own commit, which breaks the squash. Instead: resolve the conflict, `git add` the resolved files, then let the remaining `--no-commit` picks run. Only after all picks in the group have staged their changes do you run `git commit -m "..."` once to produce the single squashed commit.

Pick SHAs in chronological order (oldest → newest). Out-of-order picks produce conflicts that would have been clean otherwise.

---

## Docs and specs layout

Projects follow this layout for documentation unless a project-specific process is already in place (check the project's CLAUDE.md first):

```
docs/
  spec.md                  ← project-level: what/why, in/out scope, tech choices (lives on main)
  specs/
    feature_name/          ← one directory per feature, on its feature branch
      00_research.md       ← (optional) background reading, spike findings
      01_spec.md           ← what/why, behaviour, acceptance criteria, in/out scope
      02_plan.md           ← how: implementation approach, design decisions
      03_tasks.md          ← step-by-step tasks, maps to TDD test list
    done/                  ← completed feature directories move here on merge
```

- `docs/spec.md` is committed to main before any features begin — it is the project's authoritative what/why
- Feature subdirectories live on their feature branch and merge to main with the feature code
- Stage files are numbered so the order of work is self-documenting; `00_research.md` is optional
- On merge, move the feature directory into `docs/specs/done/` to keep the active list uncluttered

---

## Branch hygiene — keeping branches focused

Feature branches sometimes accumulate unrelated changes as a session evolves. Before raising a PR, review what's on the branch with `git log main...<branch> --oneline` and `git diff main...<branch> --stat`. If unrelated changes have crept in, split them out:

1. Create a new branch from main: `git checkout main && git checkout -b feature/housekeeping`
2. Cherry-pick only the relevant commits: `git cherry-pick <sha> <sha>`
3. Land the focused branch first, then continue feature work on a clean base

The test for whether a branch is focused: can you describe every commit on it in a single sentence that starts with the feature name? If not, it probably needs splitting.

## Detecting merged branches

When checking whether feature branches have been merged, `git branch --merged` only detects merge-commit merges — it misses branches that were fast-forward rebased onto main. Always verify with `git diff main...<branch> --stat` as well: if the diff is empty, the branch's changes are already on main regardless of how they got there.
