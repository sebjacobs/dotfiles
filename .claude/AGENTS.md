# Claude global conventions

> **MANDATORY FIRST ACTION (applies to subagents too):** before answering or calling any other tool, Read `./CLAUDE.local.md` if it exists at the root of the current working directory — even for trivial tasks. It holds per-checkout overrides that win over the project `AGENTS.md`, this file, and defaults from your user-context (e.g. how to address the user).

> **Where this config lives:** `AGENTS.md`, `settings.json` and `keybindings.json` in `~/.claude/` are symlinks into the public `~/dotfiles/.claude/`, and `~/.claude/CLAUDE.md` links to the same `AGENTS.md` because Claude Code only reads the global file under that name. `skills/`, `agents/` and `docs/` are real directories of per-entry symlinks, filled by `claude-link` from `~/dotfiles/.claude/` and the private `~/dotfiles-private/claude/`. Never create a file directly in `~/.claude/`: add it to the right repo, commit it, and run `claude-link`. Anything naming a real project, client, host or private path goes in `~/dotfiles-private`; everything else in `~/dotfiles`.

Private additions to these conventions, when that repo is cloned: @~/dotfiles-private/claude/CLAUDE.md

**Project instructions live in `AGENTS.md`, falling back to `CLAUDE.md`.** Wherever these conventions, the docs or a skill say "the project's AGENTS.md", read the project's `AGENTS.md`, or its `CLAUDE.md` if it has no `AGENTS.md`.

**Read the `~/.claude/docs/X.md` a section points to before using that tool.** Don't guess flags from memory or fall back to `--help` after a failed guess.

## Be proactive — don't ask permission for routine steps

When the next step is routine, reversible and local, do it and say what you did in the report. Asking "should I commit?" or "shall I run the tests?" costs a round-trip for an answer that is almost always yes. Just:

- Commit finished work (see Git below). Branch first if you are on `main` and the change isn't trivial.
- Run tests, linters and builds; fix the failures your change caused.
- Fix small related problems you notice (a typo, a broken link, a test you just broke), and mention them.
- Pick the conventional default when a choice has one, and state the assumption.

Stop and ask for anything **irreversible or outward-facing**: `git push`, merging to `main`, opening or editing a PR or issue, deleting files or branches you didn't create, force-pushes, history rewrites on a shared branch, anything that leaves the machine. Ask, too, when the motivation is unclear and the answer would change what you build.

## Sessions

**Start:** run `/start` (the `start-session` skill). **"Continue" means start:** "continue", "carry on", "resume", "pick up where we left off" run the full routine, not just a log catch-up. Skip it only for a quick, already-scoped task. The routine:

- Read the jotter log first, before code or `git log`: `jotter search --project <name> --since <YYYY-MM-DD> 2>&1 | tail -150` (add `--branch <branch>` to narrow). Not `jotter ls`, raw `~/.claude/projects/*.jsonl` transcripts or `git log`.
- Ask about available time and hard stops, and which mode to run in.
- Propose **one concrete goal** (in solo mode, a task list, each with its spec and plan).
- Start the `sesh` timer and set the 30-minute cron heartbeat.

**Modes** — default to solo if nothing is said:

- **Solo** (`/solo`) — the user hands over a task list and leaves. Before any code, write a short spec and plan per task (acceptance criteria, approach, assumptions) and get one sign-off. That is the last question. Then persevere, assume rather than ask, and report every decision and problem in one batch at the end. Irreversible and outward-facing actions still wait for approval: work up to that line and surface them in the report. No 7PM cut-off; the heartbeat is a progress log.
- **Classic** — collaborative: check in as you go, one goal for the session.
- **Pairing** (`/pingpong`) — TDD ping-pong: spec together, then alternate writing tests and implementing.

**Working hours:** cut-off is 7PM in classic and pairing. If a session runs past it, say so directly.

**Read the clock, don't guess.** Never estimate elapsed or remaining time from memory — read `sesh status --json` and branch on `phase` (`running → ending_soon → finished`). The heartbeat re-invokes you; `sesh` tells you the real time when it does. `/start`, `/save` and `/stop` drive the timer. Reference: `~/.claude/docs/sesh.md`.

**Logging:** session notes live in a private data repo via `jotter`; `/start`, `/save`, `/stop` and `/note` write them. For "what did we do yesterday?", use `jotter ls` / `jotter search` (`--since`/`--until`) before raw transcripts. The CLI is `jotter write` (not `add`) and needs `--project`, `--branch`, `--type`, `--content`. Reference: `~/.claude/docs/jotter.md`.

**End:** run `/stop` (`stop-session`) — it stops `sesh` and cancels the heartbeat. `/save` for a mid-session checkpoint, `/note` for a quick note. Check the project's AGENTS.md (or CLAUDE.md) for extra end-of-session steps.

## Context and subagents

- **Use `/clear` liberally** when a thread is done; `/start` restores context from the log.
- **Subagents** for exploratory work that would bloat the main context. **Background Bash** for parallel compute on existing files.
- Route by cost: **Haiku** for mechanical work, **Sonnet** by default, **Opus** for high-stakes reasoning. Reference: `~/.claude/docs/subagents.md`.
- **Waiting on a background process:** poll on a `ScheduleWakeup` timer (~270s) rather than file monitors or task output files, which are unreliable. Verify completion by checking the output itself.

**Suggest Claude Code features.** The user is learning Claude Code. When a feature would help, mention it briefly: repetition after tool use → hooks; the same change across many files → `/batch` or partitioned subagents; uncertain approach → `/plan`; a long-running task → `/loop`; a repeatable pipeline → an agent file; a constraint Claude keeps forgetting → AGENTS.md. Check with the `claude-code-guide` subagent if unsure what exists.

## Evaluating config changes

Before merging a new or rewritten AGENTS.md section, doc, skill or agent — or removing or moving one — run a quick A/B eval: two parallel subagents answer the same representative question, one with the old files and one with the new, then an Opus agent scores both 0–3 on completeness, accuracy, actionability and gaps acknowledged. Merge if the new setup scores +2 or more. Rubric and prompt templates: `~/.claude/docs/eval_config_changes.md`.

## Code comments — don't write them

Default to zero inline comments, in every language and file, tests and config included. Naming and structure say *what*, the commit message says *why*, the tests say *what the behaviour should be*; a comment restating any of them rots. In tests, a test that needs a comment wants a better name or an extracted helper.

Comment only what can't live in the code or the commit: a non-obvious external constraint, a deliberate footgun, a workaround for an upstream bug (link it). One line, and first ask whether a better name would remove the need.

## Incremental delivery

- **Smallest validated steps.** Draft the artefact, then wire it in, then remove what it replaces — separate steps, each leaving the system working with a diff you can reason about alone. Applies to code, docs, config and refactors.
- **Spec before code.** Agree a short spec; derive the tests and the implementation from it.
- **Write tests as you go**, alongside the code: a test written first says what the code should do.
- **Keep the branch green.** A temporarily skipped test is marked `skip`/`xfail` with a reason, never silently ignored.
- Spikes skip the tests, but are timeboxed and written up before the real implementation.

## Git

**Remotes.** In personal projects `origin` is the self-hosted Forgejo and the `gh` remote is only a GitHub mirror: push, raise PRs and merge on `origin`, using `fgj` rather than `gh`. Work and client repos have GitHub as `origin`. Check `git remote -v` before any push or PR.

**Invoke the skill before acting** — the rules live there so they're read at the moment they apply:

- before any `git commit` → `/commit` (grouping, message format, checklist)
- before raising or editing a PR, issue or PR comment → `/pull-request` (template, editing in place, screenshots, `fgj` flags)
- before any merge into main → `/merge-branch` (checklist, rebase, strategy, `/handover`)
- rewording, squashing or splitting existing commits → `/revise-commits`

**Always on:**

- Work on a feature branch, `feature/<name>`. Typos, doc tweaks and one-line config changes can go straight to `main`; when in doubt, ask.
- Commit finished work yourself in atomic groups and list the commits in your report. When the user says "commit" to a proposed grouping, commit all of it in that turn.
- Keep branches single-purpose: land independently useful changes separately, and early.
- Never push, raise a PR or merge until the user says so.

**Before every push:**

- `git log origin/<branch>..HEAD --oneline` — `git push` sends *every* ahead-commit; confirm each one should ship.
- Nothing starting `WIP`, `fixup!`, `squash!`, `tmp` or `DO NOT MERGE:` goes to main.
- Unexpected ahead-commits on main (e.g. from an earlier session): stop and ask.
- Never force-push main.

Reference: `~/.claude/docs/git_practices.md` — the commit-hygiene essay, branch triage and split-out recipes, squashing without interactive rebase, the docs/specs layout.

## Public files — no private references

`~/.claude/` and the dotfiles are public repos. Never put private project or repo names, private paths, personal details, internal URLs or credentials in them. Describe a pattern generically ("any repo with a `wrangler.toml`"); when the specific name is what makes it useful, put it in `~/dotfiles-private` — `claude/CLAUDE.md` for a rule, `claude/docs/` or `claude/skills/` for anything longer.

## Tooling

**macOS `sed` silently ignores GNU extensions.** BSD `sed` matches nothing for `\b`, `\+`, `\|` or `\w` and still reports success. Use `gsed` or `perl -pi -e`, and re-grep to confirm the substitution fired.

**Worktrees: always `gwt`, never raw `git worktree`** — a hard rule, including from non-interactive Bash. `gwt` copies the gitignored files in `.worktreeinclude` (`.env`, `settings.local.json`, a symlinked `CLAUDE.local.md`) that a bare `git worktree add` leaves out, and puts worktrees where its other subcommands can find them. If it isn't loaded, `zsh -ic 'gwt …'`.

- `gwt add [-b] <branch>`, `gwt rm [-f] <name>`, `gwt mv [-f] <name> <new>` (carries Claude history), `gwt ls`, `gwt status`.
- From Bash, prefer the non-cd forms: `cd "$(gwt path <name>)"`, `gwt root -p`.
- To push one changed file to other worktrees use `gwt send <path> [--to <dst>|all]`, not `gwt sync` — `sync` re-merges whole `.worktreeinclude` directories and can overwrite a worktree's own state. Use `sync` only for a worktree that has drifted.
- Full reference: the header of `zsh/gwt.zsh`.

**Python:** always `uv` — never `pip`, `pip3` or bare `python3`. Reference: `~/.claude/docs/python_tooling.md`.

**Task runner: a `Rakefile`, whatever the language** — not a justfile, Makefile or `package.json` scripts, so `rake -T` always answers "what can I run?". Give each public task a `desc`, point `default` at the everyday task, shell out with `sh`, use FileUtils helpers for files, and pair every `install` (symlinks under `PREFIX`, default `~/.local`) with an `uninstall` that removes exactly what it made. An existing project keeps its runner unless asked to migrate.

**Scratch files:** use a project-local `./tmp/` or `./log/`, not `/tmp` or `$TMPDIR`, for anything you might inspect afterwards. Setup recipe: `~/.claude/docs/workspace.md`.

## Web standards

For any static HTML page, follow `~/.claude/docs/web_standards.md`:

- **Aesthetic:** warm serif (`Times New Roman`), parchment `#f5f1e8`, max-width 620px centred — editorial, not a dashboard.
- **Accessibility:** WCAG AA contrast, visible `focus-visible` styles, `<nav aria-label>`, `lang="en"`, no `user-scalable=no`.
- **Dark mode always**, via CSS custom properties in one `@media` block.
- **No frameworks** on read-only content pages — plain HTML and CSS.
- **Reference implementations** (named in the private conventions): read their CSS first.

**Before any browser screenshot or visual check, ask the user to disable DarkReader**, and wait. It inverts light-only designs, hiding real contrast problems, and can't be neutralised from the page. Layout measurements are unaffected; anything judged by eye is not.
