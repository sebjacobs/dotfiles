# Claude global conventions

> **MANDATORY FIRST ACTION (applies to subagents too):** before answering or calling any other tool, you **must** Read `./CLAUDE.local.md` if it exists at the root of the current working directory. This is not optional and is not skippable for "trivial" tasks. `CLAUDE.local.md` contains per-checkout overrides that take precedence over the project `CLAUDE.md` and this global file. If the file does not exist, proceed normally. If it exists, its instructions override any conflicting guidance — including defaults derived from your user-context (e.g. how to address the user).

> **Note:** The entire managed `~/.claude/` config lives in `~/dotfiles` — `CLAUDE.md`, `skills/`, `agents/`, `docs/`, `settings.json`, and `keybindings.json` are all symlinks into `~/dotfiles/.claude/`. Any new files added to these directories, and any edits, must be committed in the `~/dotfiles` git repo, not here.

> **Catching up via jotter — always read the jotter log first.** Whenever a session continues, resumes, or picks up prior work ("let's continue", "carry on with X"), read the jotter log **before** reading code, running git log, or starting to act — it's the fastest way to recover what was last done and decided, and acting without it risks re-treading or contradicting recent work. Run `jotter search --project <name> --since <YYYY-MM-DD> 2>&1 | tail -150` (add `--branch <branch>` to scope to the current branch). Do **not** reach for `jotter ls`, raw `~/.claude/projects/*.jsonl` transcripts, or git log first — `jotter search` is the fastest path and the one that actually works. Full reference: `~/.claude/docs/jotter.md` — read it before invoking any other `jotter` subcommand.

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

Session notes live in a private data repo via `jotter`, not in project repos. Skills handle it: `/start`, `/save`, `/stop`, `/note` call `jotter` — no manual session note management needed.

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

Run `/stop` at the end of every session — the `stop-session` skill has the full steps. For mid-session checkpoints or stepping away briefly, use `/save`; for a quick note without committing, use `/note`.

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

## Code comments — don't write them

**The code, the commit message, and the tests should explain everything between them. Default to zero inline comments.** Intent has three durable homes: naming and structure say *what* the code does; the commit message says *why* (motivation, trade-offs, what was rejected), where it's durable and reviewable; the tests say *what the behaviour should be*. A comment that restates any of the three is noise that rots out of sync with the code.

This applies to every language and every file, including tests and config. Do not narrate constants, methods, or steps "to be helpful" — a comment on `RESULTS_SESSION_KEY = :foo` or above a self-evident method is exactly the kind to drop.

In tests, the test name and the assertions are where intent lives — not a comment above them. A descriptive test name states the behaviour being verified, and a clear assertion shows the expected outcome; a comment that restates either ("# checks the user is redirected" above a redirect assertion) is the same rot. If a test needs a comment to explain what it covers, rename it; if it needs one to explain a setup step, extract a well-named helper or fixture. The escape hatch is the same — a non-obvious external constraint in the arrange step may earn one line.

Only write a comment when the reasoning genuinely cannot live in the code *or* the commit message — a non-obvious external constraint, a deliberate footgun, a workaround for a specific upstream bug (link it). Even then: one line, and prefer to first ask whether a better name or a tiny extracted method would remove the need. When in doubt, leave it out and put the explanation in the commit body.

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
2. **Messages tell the story** — the body must *cover* three things: **Why** (what problem motivated this?), **Benefit unlocked** (what does this enable?), **Trade-offs** (why this approach over alternatives?). These three are a *content* checklist — don't turn them into literal `Why:`/`Benefit:`/`Trade-offs:` labels; weave them into flowing first-person prose matching the project's recent commits. (Section headers themselves are encouraged for longer bodies — see the format rules below — just not these three as the headers.) The diff shows the what; the message is for reasoning. A body that only describes what changed is incomplete. **If the motivation isn't clear from context, ask before writing the message — don't guess. Before writing, skim recent merged/individual commits in the repo and mirror their structure and tone.**
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

## Shell tooling — macOS `sed` silently ignores GNU extensions

The default `sed` on macOS is BSD `sed`, which does **not** support GNU extensions like `\b` (word boundary), `\+`, `\|`, or `\w`. The dangerous part: it doesn't error on them — `s/@host\b/host/g` matches *nothing* and reports success, so a "no-op" edit looks like it ran. Don't trust a `sed` substitution with GNU syntax until you've grepped the result.

- For word-boundary / GNU-regex work, use **`gsed`** (GNU sed, `brew install gnu-sed`) — it's the same syntax you'd reach for on Linux.
- No `gsed`? Use `perl -pi -e 's/\b.../.../g'` (Perl regex is always available), or fall back to a plain literal replacement when the target string isn't a substring of anything else in the file.
- Always verify the substitution actually fired (re-grep for the old pattern) rather than assuming.

## Git worktrees — use `gwt`, not raw `git worktree`

**Never run `git worktree add` / `git worktree remove` (or any raw `git worktree` subcommand) directly. Always use the `gwt` helper.** This is a hard rule, not a preference — no exceptions for "it's just a quick one" or non-interactive `Bash` calls. If `gwt` isn't loaded in the current shell, source it (`zsh -ic 'gwt …'` or source `zsh/gwt.zsh`) rather than falling back to raw `git worktree`.

Why the helper and not the plumbing: `gwt` (defined in `zsh/gwt.zsh`) places worktrees under `.claude/worktrees/`, supports fuzzy name matching, carries Claude history on rename (`gwt mv`), and — critically — honours a repo's `.worktreeinclude` to copy gitignored files (`.env`, `.claude/settings.local.json`, a symlinked `CLAUDE.local.md`) into the new worktree on `gwt add`. A bare `git worktree add` silently omits those, so the worktree loses per-checkout config and its mandated rules. A raw worktree also won't sit at the path/name `gwt`'s other subcommands expect, so later `gwt cd`/`gwt rm`/`gwt mv` can't find it.

Common commands:

- `gwt add [-b] <branch>` — create a worktree (and branch with `-b`) and cd into it
- `gwt <name>` / `gwt cd <name>` — cd into an existing worktree (fuzzy name)
- `gwt mv [-f] <name> <new-name>` — rename a worktree's directory and carry its Claude history (`~/.claude/projects/`); branch is left untouched, `-f` skips the prompt
- `gwt ls` / `gwt status` — list worktrees / full overview
- `gwt rm [-f] <name>` — remove a worktree (fuzzy name; `-f` skips the prompt)
- `gwt path [<name>]` — echo a worktree's absolute path (current if omitted)
- `gwt root [-p]` — cd back to the main worktree root (`-p` echoes the path)
- `gwt sync [<name>|--all] [-f] [--hooks]` — re-merge root's `.worktreeinclude` into a worktree (the named one, every one with `--all`, or the current one); adds missing files and refreshes stale ones without deleting the worktree's own, `-f` makes root win on a conflict, `--hooks` re-runs the `post-add` hook

The directory-changing subcommands (`add`, `cd`, `root`) rely on a shell wrapper, so from a non-interactive `Bash` call prefer the non-cd forms (`gwt path`, `gwt ls`, `gwt status`) and `cd "$(gwt path <name>)"` when you need to be inside one. Full reference and `.worktreeinclude` semantics live in the header of `zsh/gwt.zsh`.

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
- Is the first line a `<tag>: ` prefix (feat/fix/refactor/docs/chore/test/perf) followed by a short imperative summary of the *value*, not the implementation? (< 72 chars total)
- Does the body *cover* all three (as prose, not headings): **Why** (motivation), **Benefit unlocked** (what this enables), **Trade-offs** (why this approach)?
- Does the prose match the voice of the repo's recent commits? (skim them first)
- Are unrelated changes in separate commits?
- Are relevant references included, and does each one have a URL or commit SHA? Naming a doc/issue/commit without a link is dead weight to a future reader.
- Is the message being passed via HEREDOC?

**Commit grouping rules:**
- One commit per logical feature or change (not per file, not one big "various changes" commit)
- Keep unrelated changes in separate commits
- If a feature touches multiple files, those go in the **same** commit

**Commit message format:**
- **First line:** a conventional-commit tag prefix + short imperative summary, < 72 chars total. Format: `<tag>: <summary>` (e.g. `refactor: Move manufacturer list into a config YAML`, `fix: Correct mixed-case installer URLs`). Tags: `feat` (new capability), `fix` (bug fix), `refactor` (behaviour-preserving change), `docs`, `chore`, `test`, `perf`. Capitalise the summary after the tag.
- **Body — flowing first-person prose** that provides *context and reasoning*, not a restatement of the diff. The diff already shows *what* changed; the body explains **why** it was needed, **what it unlocks**, the **trade-offs / approach rationale** (including what was consciously left out), and **any key bits that might not be obvious** from reading the code. Don't enumerate the changes — let the diff speak for that. Write it the way the project's recent commits read; **skim `git log` first and mirror their structure and tone**.
- **Section headers are useful** — for anything beyond a short commit, group the prose under headers rather than leaving one long block. Match the project's existing convention; this repo's house style uses ascii-underlined bold headers, e.g. `** Background **`, `** Summary **` / `** Key Changes **`, `** Things to note **`, `** Out of scope **`. Short, single-idea commits can stay as plain prose.
- Include references where relevant — Claude session URLs, issues, PRs, external docs, research. **Every reference must carry a URL or commit SHA.** The house style is footnote markers (`[1]`, `[2]`) in the prose with the link definitions collected at the foot of the message. Same for in-repo references: cite the commit SHA, not just "as discussed in the earlier refactor".
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
- **Multiple commits** — rebase the feature branch onto main first (`git rebase main` on the feature branch, push), then merge with `gh pr merge <number> --merge` to preserve the commits grouped under a descriptive merge commit. Merge commit title: `Merge feature/<name>: <what it does>`, body: what was built and why. To carry the PR description into the merge-commit body, convert it with `~/.claude/scripts/md_to_commit.rb` (Markdown → house-style headers, wrapped at 72) — see the "Pasting a PR description into the merge commit" recipe in `~/.claude/docs/git_practices.md`.

Always rebase the feature branch onto main before merging — ensures the history is linear and conflicts are resolved on the feature branch, not on main.

**Always merge via `gh pr merge`** — never push main directly. Pushing main bypasses GitHub's merge mechanism; the PR only appears merged by inference rather than being properly closed. `gh pr merge` closes the PR, records the merge event, and keeps the GitHub history canonical.

**Process:**
1. **Always start on a feature branch** — never work directly on main, even for small changes. Create a branch before writing any code: `git checkout -b feature/<name>`
2. Run `git status` and `git diff --stat` to survey all dirty changes
3. Show the full diff — not just the stat — so the user can review every line before anything is merged. For branches with many files, diff file-by-file or skip all-addition new files (they have no "what changed") and diff only modified files: `git diff main...<branch> -- file1 file2`
4. Propose a grouping to the user and wait for approval
5. Stage and commit each group sequentially
6. **Never merge or raise a PR until the user explicitly says to** — propose it, then wait
7. **After merging — preserve the branch's context with `/handover`.** Once a feature branch is merged and about to be deleted, run `/handover` to distil its session log into a single handover entry on `main` so the branch's history and decisions survive its removal. Then delete the merged branch (and its worktree, via `gwt rm`). This applies to local-only merges too, not just `gh pr merge`.

**Before you push — checklist:**
> Re-read this before every `git push`, especially to main.
- Run `git log origin/<branch>..HEAD --oneline` and confirm every listed commit is intended to ship. `git push` pushes *all* ahead-commits, not just the one you just made.
- **Never push WIP commits to main.** If a commit message starts with `WIP`, `fixup!`, `squash!`, `tmp`, or similar, it doesn't belong on main — rebase/squash it first, or move it to a branch.
- **Dummy / throwaway / test / verification commits on a feature branch must be prefixed `DO NOT MERGE:`.** Anything that's only on the branch to exercise CI, reproduce a bug, sanity-check a workflow change, or otherwise prove a point — and is not meant to ship — gets this prefix. Examples: a deliberately failing test to confirm an artifact upload, a temporary `puts` in production code to verify a log path, a hardcoded value to flush out a downstream behaviour. The prefix makes them impossible to miss during pre-merge branch cleanup — revert (or drop them with a rebase) before raising the PR for review, or at the very latest before merging.
- If you find unexpected ahead-commits on main (e.g. from a previous session), pause and surface them to the user before pushing. Don't assume they're safe to ship.
- Never `git push --force` to main.

**Feature branch PRs:**
PR descriptions follow the same philosophy as commit messages — explain the *why*, not just the *what*, and **defer the per-change detail to the commit messages** rather than re-narrating the diff. The body orients the reviewer; the commits carry the specifics. Structure (use these exact `##` headings):

1. **## Motivation** — lead with the *why*, kept high-level: a paragraph or two on the problem this solves or the capability it unlocks, the reasoning behind the approach, and the scope boundary (what this part deliberately does *not* do). Don't enumerate the changes here. Illustrate the problem with one concrete example rather than listing every instance of it — e.g. "a `setup_pagination` whose branches ran back-to-front" lands better than a full inventory of the tangles. For a stacked PR, open by naming the part it follows and linking it. If the PR is behaviour-preserving except for a deliberate change, call that exception out here — and note that it surfaces as a test edit rather than silent drift.
2. **## Summary** — a short bullet list of the significant changes at a high level (not exhaustive, not file-by-file). Weave any gotchas, trade-offs, and "things to note" into the relevant bullet or a short following sentence rather than giving them their own heading. End with **"See individual commit messages for the details."** Fold references inline where they belong (every reference carries a URL or commit SHA; footnote style `[1]`/`[2]` when there are several). For a stacked PR, close with a line naming the base branch and a compare link to the part's own diff, plus the merge/rebase order. **Don't link to predecessor/draft PRs as predecessors** — but the part-N cross-links between live stacked PRs are the point, keep those.
3. **## Questions/Feedback** — include by default. Specific questions for reviewers: naming calls, design decisions, judgement calls, anything you'd want a second opinion on. Better than a vague "thoughts?" — it directs attention where input is actually useful. Only skip if there is genuinely nothing to ask; when in doubt, surface at least one real question (e.g. "is the scope right?", "I went with X over Y because Z — agree?").

Do **not** add separate `Key changes`, `Gotchas`, `References`, or `Test plan` headings — that older six-heading template is retired. Their content folds into Motivation and Summary as above. Add a `## TODO` checklist only when there are remaining steps on the branch, so the PR tracks what's left.

Example (a stacked, behaviour-preserving refactor PR):

```markdown
## Motivation

With [part 3](…/pull/687)'s characterization net in place, this part untangles
`WidgetsController#index` — the slice's most tangled method. It read as one long
procedure (e.g. a `setup_pagination` whose branches ran back-to-front), and the filtering
feature still to come needs it readable first.

Every commit is behaviour-preserving and pinned by part 3's specs, **with one deliberate
exception**: a repeat request now queries the cache once, not twice. That surfaces as a test edit
(the part 3 spec flips from `.twice` to `.once`) rather than as silent drift.

## Summary

- Extract the empty-results redirect into a `redirect_on_empty_filter` guard.
- Untangle `setup_pagination` — nil-first ordering, named predicates, and rebuild cached
  bounds instead of recomputing them.
- Extract `rows_for(query)` and `row_html(record)` from the inline builder.

See individual commit messages for the details.

This is stacked on [part 3](…/pull/687) — its base is `feature/widget-list-p3`, so the diff
here is only this part's commits ([compare](…/compare/feature/widget-list-p3...feature/widget-list-p4)).
Merge after #687 lands (and rebase onto `main` at that point).

## Questions/Feedback

- Do `sorted` / `within_page_bounds` / `redirect_on_empty_filter` read ok?
- The query-once-not-twice flip is the only behaviour change — happy folding it in here?
```

**Editing PR descriptions, issues, comments — fetch live state first, edit in place, never regenerate from a remembered template.** The user is often editing the same artifact concurrently in the GitHub UI. Regenerating the whole body from your last-known version silently stomps their edits. The right pattern is always: `gh pr view <n> --json body --jq .body > /tmp/body.md` → `Edit` only the line that needs changing → `gh pr edit <n> --body-file /tmp/body.md`. Applies equally to issue bodies, PR comments, anywhere a human and you might both write. If a small targeted edit isn't possible (e.g. major restructure), confirm with the user before pushing a full rewrite.

**Labels:** don't bother with PR labels — skip `gh label list` and create PRs without a label unless explicitly asked to add one.

**When to skip a feature branch:**
Small, self-contained changes (typo fixes, doc tweaks, single-line config changes) can be committed directly to main — not everything needs a branch and PR. This is a judgement call each time; when in doubt, ask.

**Branch hygiene:** if unrelated changes crept into a feature branch, split them out before raising a PR — focused branches merge sooner and conflict less. The test: can every commit be described in one sentence starting with the feature name?

**Detecting merged branches:** `git branch --merged` misses fast-forward rebased branches — always verify with `git diff main...<branch> --stat`. Empty diff = already on main.

See `~/.claude/docs/git_practices.md` for the docs/specs directory layout, the full branch hygiene split-out recipe, and the branch triage runbook.
