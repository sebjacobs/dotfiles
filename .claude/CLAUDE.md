# Claude global conventions

> **Note:** This file (`~/.claude/CLAUDE.md`) is a symlink into `~/dotfiles`. Any changes must be committed in the `~/dotfiles` git repo, not here.

## Session start routine

At the start of each conversation:
1. Ask how much time is available to pair
2. Ask about any hard stops during the session (lunch, a run, a call, etc.)
3. Read the project's planning files to understand current priorities
4. Suggest **one concrete goal** that fits the time available — not a wish list
5. **Set up a recurring 30-minute session timer** using `CronCreate` — fires every 30 minutes while the REPL is idle, prompting a brief check-in on progress and proximity to any hard stop. Use a cron like `*/30 * * * *` with `recurring: true`. Do this immediately once you have the session start time, without asking — it's always useful.

Use the answers to pace the session — flag if a task looks too large to finish before the hard stop, and remind the user when they're approaching it.

## Working hours

Cut-off is 7PM. If a session is running past 7PM, say so directly — don't let it slide quietly. Early starts are fine.

## Pomodoro breaks

Every 45 minutes of an active session, gently check in: "It's been ~45 mins — would you like to take a 15 min break?" Keep it soft and optional, not a hard interrupt. Note the session start time and any hard stops from the session start routine to track this accurately.

## Subagents and parallelisation

**Subagents for research + build; background Bash for parallel compute.**

- Use a subagent (general-purpose or Explore) when a task has many exploratory steps — browsing, reading files, writing a script, running it — that would bloat the main context. The subagent does all the work and returns a clean result.
- Use background `Bash` tool calls for parallelising compute work on existing files (e.g. chunked scraping, batch processing). Simpler, no permission overhead.

**Background subagent permission gotcha:** background subagents must have all tool permissions pre-approved at spawn time. Tools not approved upfront are auto-denied at runtime — no prompt is relayed to the user. Three options if a subagent needs `Bash`:
  1. **Define a named subagent** in `.claude/agents/name.md` with a `tools:` frontmatter field — Claude Code prompts for those tools upfront before launching: `tools: Bash, Read, Write, Glob`
  2. Run it in **foreground** mode (no `run_in_background: true`) so permission prompts come through normally
  3. Skip subagents and use background `Bash` jobs directly — they inherit the session's already-approved permissions

**Foreground subagents** relay permission prompts and `AskUserQuestion` calls normally — use these when the task may need interactive permission grants.

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
- Include links/references where relevant — e.g. Claude chat session URLs, GitHub issues, PRs, external docs, or research that informed the change
- Always end with `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
- Use a HEREDOC to pass the message to `git commit -m`

**Merge strategy (feature branches → main):**

Before merging, always count commits: `git log main...<branch> --oneline | wc -l`

- **Single commit** — rebase fast-forward: `gh pr merge <number> --rebase` (no merge commit, linear history)
- **Multiple commits** — rebase the feature branch onto main first (`git rebase main` on the feature branch, push), then merge with `gh pr merge <number> --merge` to preserve the commits grouped under a descriptive merge commit. Merge commit title: `Merge feature/<name>: <what it does>`, body: what was built and why.

Always rebase the feature branch onto main before merging — ensures the history is linear and conflicts are resolved on the feature branch, not on main.

**Always merge via `gh pr merge`** — never push main directly. Pushing main bypasses GitHub's merge mechanism; the PR only appears merged by inference rather than being properly closed. `gh pr merge` closes the PR, records the merge event, and keeps the GitHub history canonical.

**Process:**
1. **Always start on a feature branch** — never work directly on main, even for small changes. Create a branch before writing any code: `git checkout -b feature/<name>`
2. Run `git status` and `git diff --stat` to survey all dirty changes
3. Show the full diff — not just the stat — so the user can review every line before anything is merged. For branches with many files, diff file-by-file or skip all-addition new files (they have no "what changed") and diff only modified files: `git diff main...<branch> -- file1 file2`
4. Propose a grouping to the user and wait for approval
5. Stage and commit each group sequentially
6. **Never merge or raise a PR until the user explicitly says to** — propose it, then wait

**Feature branch PRs:**
PR descriptions follow the same philosophy as commit messages — explain the *why*, not just the *what*. Structure:

1. **Summary** — one short paragraph: what this PR does, what problem it solves or capability it enables, and the reasoning behind the approach
2. **Key changes** — brief bullet list of the significant files/areas touched (not exhaustive)
3. **Gotchas / things to be aware of** — anything non-obvious: migration steps, dependencies, trade-offs made, things that might bite a reviewer or future contributor
4. **References** — links to anything that informed the work: Claude session URLs, GitHub issues, external docs, research, prior art
5. **Test plan** — checklist of how to verify the change works

Include a TODO checklist for any remaining steps not yet done on the branch — this makes the PR a live tracker of what's left.

**Feature development approach:**
Before starting a new feature, write a short spec (spec-kit style: `spec.md` for what/why, `plan.md` for how) and agree on it before writing any code. From the agreed spec, use TDD — write tests first to capture the acceptance criteria, then implement to make them pass. This keeps features focused, avoids scope drift, and ensures correctness from the start.

Exception: for spikes, prototypes, or proof-of-concept work the goal is learning rather than shipping — skip the spec gate and TDD overhead, but timebox the exploration and write up what was learned before starting the real implementation.

**When to skip a feature branch:**
Small, self-contained changes (typo fixes, doc tweaks, single-line config changes) can be committed directly to main — not everything needs a branch and PR. This is a judgement call each time; when in doubt, ask.

**Branch hygiene — keeping branches focused:**
Feature branches sometimes accumulate unrelated changes as a session evolves. Before raising a PR, review what's on the branch with `git log main...<branch> --oneline` and `git diff main...<branch> --stat`. If unrelated changes have crept in, split them out:

1. Create a new branch from main: `git checkout main && git checkout -b feature/housekeeping`
2. Cherry-pick only the relevant commits: `git cherry-pick <sha> <sha>`
3. Land the focused branch first, then continue feature work on a clean base

The test for whether a branch is focused: can you describe every commit on it in a single sentence that starts with the feature name? If not, it probably needs splitting.

**Branch cleanup:**
When checking whether feature branches have been merged, `git branch --merged` only detects merge-commit merges — it misses branches that were fast-forward rebased onto main. Always verify with `git diff main...<branch> --stat` as well: if the diff is empty, the branch's changes are already on main regardless of how they got there.
