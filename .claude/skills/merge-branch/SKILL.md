---
name: merge-branch
description: Merge a finished feature branch into main — the pre-merge checklist, rebasing with reset author dates (including stacked branches), choosing fast-forward versus a merge commit, writing the merge-commit body from the PR description, then `/handover` and branch cleanup. Use before every `gh pr merge`, `fgj pr merge` or `git merge` into main, and when the user says "merge it", "merge the PR", "land this", "ship the branch".
---

# Merge a branch

Merging is outward-facing: **only merge once the user has explicitly said to.** Never propose a merge and carry it out in the same step.

Check the project's AGENTS.md (or CLAUDE.md if it has none) first. A solo repo may merge locally with `git merge` instead of through a PR, and that override wins over the PR mechanics below.

## Before merging

- **The user has said to merge.**
- **The full diff has been reviewed**, not just `--stat`. Show the modified files to the user: `git diff main...<branch> -- <file>…`. All-addition new files can be skipped since they have no "what changed".
- **The branch is focused.** Every commit can be described in one sentence starting with the feature name. If not, split it first (see the branch hygiene recipe in `~/.claude/docs/git_practices.md`).
- **The history is clean.** `git log main...<branch> --oneline` again — review may have added fixups. Squash them into the commit they belong with (`/revise-commits`) and drop any `DO NOT MERGE:` commits.
- **The PR description is written**, and any `TODO before merge` checklist in it is complete.
- **The branch is rebased onto the latest main.**
- **CI is green and any required reviews are in** (`gh pr checks <n>`, `gh pr view <n> --json reviewDecision`). Don't merge around a failing or pending check.

## Rebase, resetting author dates

A rebase keeps each commit's original author date, so a branch written over several days lands on main stamped earlier than commits already there. `git log` by date and by topology then disagree, and "what shipped when" stops being answerable. Reset the dates so commits sit where they entered main.

Use `grod` (`zsh/git_aliases.zsh`): `git rebase origin/main --reset-author-date` with the trunk worked out for you.

For a stack, `grod` only fits the bottom branch — rebasing each part onto main on its own gives the shared commits different SHAs in every branch. Chain them bottom to top, each onto the rebased branch below it:

```bash
git rebase --onto <rebased-lower-tip> <old-lower-tip> <branch> --reset-author-date --no-keep-empty
```

`--no-keep-empty` drops the empty "force CI rebuild" commits a plain rebase keeps.

Rebasing a pushed branch needs `git push --force-with-lease` — ask first, as with any push.

## Pick the strategy

Count the commits: `git log main...<branch> --oneline | wc -l`.

| Commits | GitHub | Forgejo (`fgj`) |
|---|---|---|
| One | `gh pr merge <n> --rebase` | `fgj pr merge <n> --merge-method rebase` |
| Several | `gh pr merge <n> --merge` | `fgj pr merge <n> --merge-method merge` |

One commit fast-forwards with no merge commit. Several keep their grouping under a merge commit titled `Merge feature/<name>: <what it does>`, whose body says what was built and why. To carry the PR description into that body, convert it with `~/.claude/scripts/md_to_commit.rb` — the recipe is under "Pasting a PR description into the merge commit" in `~/.claude/docs/git_practices.md`.

**Always merge through the PR, never by pushing main.** Pushing main leaves the PR merged only by inference instead of properly closed, and loses the merge event.

## After merging

1. Run `/handover` to distil the branch's session log into one entry on `main`, so its decisions survive the branch being deleted. This applies to local merges too.
2. Delete the merged branch, and its worktree with `gwt rm`.

To check whether an old branch is already merged, don't trust `git branch --merged` — it misses fast-forward rebased branches. An empty `git diff main...<branch> --stat` means it's on main.
