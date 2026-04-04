---
name: branch-audit
description: Audit branches in the current git repo — identify which are safe to delete, which have open PRs, and which need a decision. Use when asked to "audit branches", "clean up branches", "triage branches", or similar.
---

# Branch Audit

Produces a categorised branch status table, then stops. Does not delete or modify anything unless the user explicitly asks.

---

## Steps

### 1 — Get all local branches (excluding main)

```bash
git branch --format='%(refname:short)' | grep -v '^main$'
```

### 2 — For each branch, check merged status

Two checks are needed — `git branch --merged` only catches merge-commit merges, not rebase fast-forwards:

```bash
# Check 1: is the branch an ancestor of main? (merge-commit merge)
git merge-base --is-ancestor <branch> main && echo "ANCESTOR"

# Check 2: is the diff empty? (rebase fast-forward — changes are on main, branch is stale)
git diff main...<branch> --stat
```

A branch is **safe to delete** if either:
- It is an ancestor of main (`merge-base` returns true), OR
- `git diff main...<branch> --stat` produces no output (empty diff)

### 3 — Cross-reference with GitHub PR state

```bash
gh pr list --state all --limit 100 --json number,title,headRefName,state,mergedAt
```

Map each branch to its PR (if any). PR states:
- `OPEN` — active work, do not touch
- `MERGED` — PR merged; if diff is also empty, safe to delete
- `CLOSED` (not merged) — abandoned PR; flag for decision
- No PR — has changes but was never proposed; flag for decision

### 4 — Output the categorised table

Present results in three sections:

**Safe to delete** — empty diff or merged ancestor. No risk.
| Branch | PR | Notes |
|--------|-----|-------|

**Active — open PR, leave alone**
| Branch | PR | Size (files changed) |
|--------|-----|---------------------|

**Needs a decision** — closed/abandoned PR, or changes with no PR
| Branch | PR state | Situation |
|--------|----------|-----------|

For the "Needs a decision" rows, include a one-line assessment: e.g. "superseded by X", "orphaned — no PR, 3 files changed", "PR closed without merging".

### 5 — Stop

Do not delete, push, or propose any git commands. Present the table and ask the user what they'd like to do. If they say "delete the safe ones", proceed branch by branch — local first, then remote — confirming each group before acting.

---

## Notes

- Run this from the repo root
- Works in any git repo with a `main` branch; if the default branch is `master` or something else, adjust the `main` references
- Remote-only branches (no local checkout) appear in `git branch -a` with `remotes/origin/` prefix — include them in the audit but note they are remote-only
- If `gh` is not available, skip the PR cross-reference and note that PRs could not be checked
