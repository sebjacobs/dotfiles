# Claude global conventions

## Session start routine

At the start of each conversation:
1. Ask how much time is available to pair
2. Ask about any hard stops during the session (lunch, a run, a call, etc.)
3. Read the project's planning files to understand current priorities
4. Suggest **one concrete goal** that fits the time available — not a wish list

Use the answers to pace the session — flag if a task looks too large to finish before the hard stop, and remind the user when they're approaching it.

## Working hours

Cut-off is 7PM. If a session is running past 7PM, say so directly — don't let it slide quietly. Early starts are fine.

## Pomodoro breaks

Every 45 minutes of an active session, gently check in: "It's been ~45 mins — would you like to take a 15 min break?" Keep it soft and optional, not a hard interrupt. Note the session start time and any hard stops from the session start routine to track this accurately.

## Git workflow

Changes accumulate as dirty working tree state during a session. Do **not** commit automatically — wait for the user to confirm they are happy with each feature. Then group changes into meaningful, feature-scoped commits.

**Commit grouping rules:**
- One commit per logical feature or change (not per file, not one big "various changes" commit)
- Keep unrelated changes in separate commits
- If a feature touches multiple files, those go in the **same** commit

**Commit message format:**
- First line: short imperative summary (< 72 chars)
- Blank line, then a body paragraph explaining **why** the change was made — the motivation, not just what changed
- If multiple files are involved, a brief `Changes:` list of what was done
- Always end with `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
- Use a HEREDOC to pass the message to `git commit -m`

**Merge strategy (feature branches → main):**
- **Single commit** — rebase (fast-forward onto main, no merge commit)
- **Multiple commits** — rebase the feature branch onto main first, then merge with `--no-ff` to preserve the commits grouped under a merge commit. Use a descriptive merge commit message that summarises the feature — title line says what the feature is, body explains what was built and why. This keeps the summary in the git history as well as on GitHub.

Always rebase the feature branch onto main before merging via GitHub — ensures the history is linear and conflicts are resolved on the feature branch, not on main. When writing merge commit messages, include the feature name in the title, e.g. `Merge feature/auth: Add OAuth2 login flow`.

**Process:**
1. Run `git status` and `git diff --stat` to survey all dirty changes
2. Propose a grouping to the user and wait for approval
3. Stage and commit each group sequentially

**Feature branch PRs:**
When creating a PR for a feature branch, include a TODO checklist in the PR description (or as an early comment) listing the remaining steps to completion. Keep it updated as work progresses. This makes the PR a live tracker of what's left to do on the branch.

**When to skip a feature branch:**
Small, self-contained changes (typo fixes, doc tweaks, single-line config changes) can be committed directly to main — not everything needs a branch and PR. This is a judgement call each time; when in doubt, ask.

**Branch cleanup:**
When checking whether feature branches have been merged, `git branch --merged` only detects merge-commit merges — it misses branches that were fast-forward rebased onto main. Always verify with `git diff main...<branch> --stat` as well: if the diff is empty, the branch's changes are already on main regardless of how they got there.
