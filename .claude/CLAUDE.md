# Claude global conventions

> **Note:** The entire managed `~/.claude/` config lives in `~/dotfiles` — `CLAUDE.md`, `skills/`, `agents/`, `docs/`, `settings.json`, and `keybindings.json` are all symlinks into `~/dotfiles/.claude/`. Any new files added to these directories, and any edits, must be committed in the `~/dotfiles` git repo, not here.

## Evaluating global and project config changes

Before merging a change to CLAUDE.md, `~/.claude/docs/`, or a project skill, run a quick A/B eval to verify it improves agent responses rather than just adding noise.

**Triggers:** new CLAUDE.md section, new docs file, significant rewrite, content removal, moving content from project → global, extracting a workflow into a skill, or creating/updating an agent definition.

**Pattern:**
1. Write a representative test question that directly exercises the changed content
2. Spawn two parallel subagents — Setup A reads only the old files, Setup B reads the new setup
3. Ask both the same question; launch in parallel
4. Run an Opus eval agent scoring both on: **Completeness, Accuracy, Actionability, Gaps acknowledged** (0–3 each)
5. Merge if Setup B scores +2 or more; investigate if neutral or negative

See `~/.claude/docs/eval_config_changes.md` for the full rubric, agent prompt templates, and a worked example.

## Session logging

Session notes live in a private data repo via `jotter`, not in project repos. Skills handle it: `/start`, `/save`, `/finish`, `/break` call `jotter` — no manual session note management needed.

For retrospective queries ("what did we do yesterday?"), reach for `jotter ls` / `jotter search` (both support `--since`/`--until`) before diving into Claude Code's raw transcripts (`~/.claude/projects/*.jsonl`).

**Before invoking `jotter` directly from the shell, read `~/.claude/docs/jotter.md` for the exact subcommand and flag forms — don't guess from memory.** The CLI uses `jotter write` (not `add`), requires `--project`, `--branch`, `--type`, `--content`, and the doc has copy-pasteable one-liners. Same rule applies to any tool this file points at a `~/.claude/docs/X.md` reference for: read the doc first, don't fall back to `--help` after a failed guess.

See `~/.claude/docs/jotter.md` for the full reference — storage layout, commands, git integration, and retrospective query patterns with examples.

## Session start routine

Run `/start` at the beginning of every session — the `start-session` skill has the full steps.

Principles:
- Ask about available time and hard stops before reading anything
- Ask if the session should use ping-pong TDD mode — invoke `/pingpong` if yes
- Propose **one concrete goal** — not a wish list
- Set a cron timer so the session is paced automatically
- Cut off at **7PM** — flag it directly if the session is running late

## Session end routine

Run `/finish` at the end of every session — the `finish-session` skill has the full steps. Also handles mid-session breaks (`/break`) in quick mode.

Principles:
- Check the project's CLAUDE.md for any additional session-end requirements

## Working hours

Cut-off is 7PM. If a session is running past 7PM, say so directly — don't let it slide quietly. Early starts are fine.

## Managing context

**Use `/clear` liberally.** Context is the scarcest resource in a session — clearing it when a thread is done keeps later work sharp. Session logs make `/clear` cheap: `/start` restores context from the data repo automatically.

Within a session, the main levers for keeping context lean:

- **`/clear`** — reset when a thread concludes or goes stale
- **Subagents for exploratory work** — browsing, reading many files, running scripts; the subagent absorbs the cost and returns a summary, leaving the main context clean
- **Background Bash for parallel compute** — chunked processing, batch jobs; simpler than subagents, inherits approved permissions

## Subagents and parallelisation

**Subagents for research + build; background Bash for parallel compute.** Use a subagent when a task has many exploratory steps that would bloat the main context. Use background `Bash` for parallel compute on existing files. Route by cost: **Haiku** for mechanical execution, **Sonnet** default, **Opus** for high-stakes reasoning.

See `~/.claude/docs/subagents.md` for the full reference — background permission gotcha, agent-vs-skill table, partitioning pattern, and the model routing rubric.

## Polling vs monitoring for long-running tasks

When waiting for a background process (download, build, test run) to complete before taking a follow-up action, **prefer polling on a ScheduleWakeup timer** over file monitors or watching background task output files. File monitors pick up stale changes unreliably, and background task output files are often empty or unbuffered until the process exits — neither gives a clean signal. A timer every ~270s is reliable and cheap. Always verify completion directly (check the output, inspect the artefact) rather than trusting the signal source.

## Proactively suggest Claude Code features

You are working with a user who is actively learning Claude Code. When you notice a pattern that a Claude Code feature could improve — repetitive manual steps, bulk file changes, risky PRs, long-running polls, complex decisions — mention it briefly without derailing the task.

If you're unsure what's currently available, use the `claude-code-guide` subagent to look it up before suggesting. Don't guess or cite stale knowledge.

Common patterns: manual repetition after tool use → hooks; same change across many files → `/batch` or partitioned subagents; uncertain approach → `/plan`; long-running task to monitor → `/loop`; repeatable self-contained pipeline → agent file; recurring constraint Claude keeps forgetting → belongs in CLAUDE.md; high-volume mechanical work → Haiku subagent; high-stakes reasoning → Opus.

## Incremental delivery

Break work into the smallest steps that can each be validated independently. Draft the artefact first, then wire it in, then remove what it replaces — separate steps, not one. This applies to code, docs, config changes, and refactors equally. Each step should leave the system in a working state and produce a diff you can read and reason about in isolation.

The git principles below (atomic commits, single-purpose branches) are the downstream expression of this — small steps make atomic commits natural rather than effortful.

**Spec before code.** Before starting a feature, write a short spec and agree on it. From the agreed spec, derive both the tests (acceptance criteria) and the implementation. This keeps features focused and avoids scope drift — you can't drift from a boundary you've already drawn.

**Write tests as you go.** Tests define what "done" means for each step. Write them alongside the code, not after. A test written after the fact describes what the code does; a test written first describes what it should do — that's a meaningful difference when requirements are still being settled.

**Keep the branch green.** Don't let failing tests accumulate. A red branch means you can't tell whether a new failure is from your current change or a previous one. If a test must be temporarily skipped, mark it explicitly (`skip`/`xfail`) with a reason — never silently ignore it.

Exception: spikes and proof-of-concept work are exploration, not delivery — skip the test overhead, but timebox the spike and write up what was learned before starting the real implementation.

## Workspace hygiene — prefer project-local scratch dirs

For temporary files and log output, use a **project-local directory** (`./tmp/`, `./log/`) rather than `/tmp`, `$TMPDIR`, or the user's home dir. Only use system temp dirs for genuinely ephemeral single-invocation fixtures — anything you might want to inspect afterward belongs in-tree.

See `~/.claude/docs/workspace.md` for the setup recipe (`.gitkeep` + `.gitignore` pattern).

## Git workflow

Changes accumulate as dirty working tree state during a session. Do **not** commit mid-feature without checking. When a task is complete and there are uncommitted changes, propose commit groupings and wait for the user to confirm they make sense — then commit. Don't wait to be asked whether to commit; take the initiative to propose, then act after approval.

**Five principles (the why behind the rules below):**

1. **Atomic commits** — each commit has one reason to exist. If you can describe it with "and", split it. Atomic commits can be reverted independently, bisected to find regressions, and reviewed in isolation.
2. **Messages tell the story** — the body must answer three questions: **Why** (what problem motivated this?), **Benefit unlocked** (what does this enable?), **Trade-offs** (why this approach over alternatives?). The diff shows the what; the message is for reasoning. A body that only describes what changed is incomplete. **If the motivation isn't clear from context, ask before writing the message — don't guess.**
3. **Revise before sharing** — your working history is a draft. Squash fixups, reorder for clarity, remove noise before pushing. The goal is a history someone else can read, not a truthful log of false starts.
4. **Single-purpose branches** — keep branches focused. If development produced something independently useful, cherry-pick it out and land it early. Smaller PRs merge sooner, conflict less, and deliver value faster.
5. **Linear history** — rebase feature branches onto main before merging. Group related commits under a descriptive merge commit. A readable history is a debugging tool.

See `~/.claude/docs/git_practices.md` for the full reference — FutureLearn engineering post on commit hygiene and the branch triage runbook.

## Public files — no private references

`~/.claude/` (CLAUDE.md, docs/, skills/, agents/) and dotfiles are committed to public repos. Never include in these files:

- Private project names, repo names, or file paths
- Personal details (name, email, employer, location)
- Internal URLs, API endpoints, or credentials
- Anything that would reveal information you wouldn't post publicly

When referencing a pattern or example, describe it generically (e.g. "any repo with a `wrangler.toml`") rather than naming a specific project.

---

## Python tooling

Always use `uv` for Python projects — never `pip`, `pip3`, or bare `python3`.

See `~/.claude/docs/python_tooling.md` for the full reference.

## Web standards

When building any static HTML page, follow `~/.claude/docs/web_standards.md`. Key points:

- **Aesthetic:** warm serif (`Times New Roman`), parchment background `#f5f1e8`, max-width 620px centred — editorial, not a dashboard
- **Accessibility (non-negotiable):** WCAG AA contrast minimum, visible focus styles (`focus-visible`), `<nav aria-label>` for navigation, `lang="en"`, no `user-scalable=no`
- **Dark mode:** always — use CSS custom properties so it's one `@media` block
- **No frameworks:** plain HTML + CSS only; no React/Vue/Tailwind on read-only content pages
- **Reference implementations:** any personal project with a `wrangler.toml` and `public/` directory in `~/Tech/Projects/personal/current/` — read the CSS there first

**Before you commit — checklist:**
> Re-read this before staging anything.
- Has the user confirmed they're happy with the feature? Never commit automatically.
- Is this the smallest unit of change that delivers value on its own? (atomic — could it be reverted independently without breaking anything?)
- Does each commit have exactly one reason to change? (Single Responsibility Principle — if you can describe it with "and", split it)
- Is the first line a short imperative summary of the *value*, not the implementation? (< 72 chars)
- Does the body answer all three: **Why** (motivation), **Benefit unlocked** (what this enables), **Trade-offs** (why this approach)?
- Are unrelated changes in separate commits?
- For multi-file commits, is there a `Changes:` list in the body?
- Are relevant links/references included? (Claude session URLs, GitHub issues, external docs)
- Is the message being passed via HEREDOC?

**Commit grouping rules:**
- One commit per logical feature or change (not per file, not one big "various changes" commit)
- Keep unrelated changes in separate commits
- If a feature touches multiple files, those go in the **same** commit

**Commit message format:**
- First line: short imperative summary (< 72 chars)
- Blank line, then a body that answers three questions:
  1. **Why** — what problem or need motivated this change?
  2. **Benefit unlocked** — what does this enable that wasn't possible before?
  3. **Trade-offs / approach rationale** — why this approach over the alternatives? What was consciously decided not to do?
- A body that only describes *what* changed is incomplete — future contributors need the reasoning, not just the diff
- If multiple files are involved, a brief `Changes:` list of what was done
- Include links/references where relevant — e.g. Claude chat session URLs, GitHub issues, PRs, external docs, or research that informed the change
- Always end with `Co-Authored-By: Claude [model] <noreply@anthropic.com>` — use the actual model you're running on (available in your system context, e.g. `Claude Sonnet 4.6`)
- Use a HEREDOC to pass the message to `git commit -m`

**Branch cleanup before raising a PR and before merging:** review every commit with `git log main...<branch> --oneline`. Cleanup commits (renames, fixups, "oops" corrections) are noise — squash them into the commit they belong with. Every commit should tell one clear story. Do this twice: once before raising the PR, and again before merging in case review feedback triggered more fixup commits.

**Squashing without interactive rebase:** interactive rebase isn't available in Claude Code — rebuild the branch with `git cherry-pick --no-commit` instead. See `~/.claude/docs/git_practices.md` for the exact recipe.

**Before you merge — checklist:**
> Re-read this before running any merge command.
- Has the user explicitly said to merge? Never propose and proceed in the same step.
- Has the full diff been reviewed (not just `--stat`)? Show modified files to the user before merging.
- Is the branch focused — can every commit be described in one sentence starting with the feature name? If not, split it first.
- Has the branch been rebased onto the latest main?
- Is the PR description written (summary, key changes, gotchas, references, test plan)?
- Is the `## TODO before merge` checklist in the PR description complete — no outstanding items?
- Single commit → `--rebase`; multiple commits → `--merge` with a descriptive merge commit title
- Never push main directly — always use `gh pr merge`

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

**Before you push — checklist:**
> Re-read this before every `git push`, especially to main.
- Run `git log origin/<branch>..HEAD --oneline` and confirm every listed commit is intended to ship. `git push` pushes *all* ahead-commits, not just the one you just made.
- **Never push WIP commits to main.** If a commit message starts with `WIP`, `fixup!`, `squash!`, `tmp`, or similar, it doesn't belong on main — rebase/squash it first, or move it to a branch.
- If you find unexpected ahead-commits on main (e.g. from a previous session), pause and surface them to the user before pushing. Don't assume they're safe to ship.
- Never `git push --force` to main.

**Feature branch PRs:**
PR descriptions follow the same philosophy as commit messages — explain the *why*, not just the *what*. Structure:

1. **Summary** — one short paragraph: what this PR does, what problem it solves or capability it enables, and the reasoning behind the approach
2. **Key changes** — brief bullet list of the significant files/areas touched (not exhaustive)
3. **Gotchas / things to be aware of** — anything non-obvious: migration steps, dependencies, trade-offs made, things that might bite a reviewer or future contributor
4. **References** — links to anything that informed the work: Claude session URLs, GitHub issues, external docs, research, prior art
5. **Test plan** — checklist of how to verify the change works

Include a TODO checklist for any remaining steps not yet done on the branch — this makes the PR a live tracker of what's left.

**Labels:** always add an appropriate label when creating a PR. Check available labels with `gh label list` and pick the best fit (e.g. `spike/idea`, `feature`, `spec`, `documentation`, `bug`).

**When to skip a feature branch:**
Small, self-contained changes (typo fixes, doc tweaks, single-line config changes) can be committed directly to main — not everything needs a branch and PR. This is a judgement call each time; when in doubt, ask.

**Branch hygiene:** if unrelated changes crept into a feature branch, split them out before raising a PR — focused branches merge sooner and conflict less. The test: can every commit be described in one sentence starting with the feature name?

**Detecting merged branches:** `git branch --merged` misses fast-forward rebased branches — always verify with `git diff main...<branch> --stat`. Empty diff = already on main.

See `~/.claude/docs/git_practices.md` for the docs/specs directory layout, the full branch hygiene split-out recipe, and the branch triage runbook.
