<p align="center">
  <img src="../assets/logo.png" alt="Dennis" width="220">
</p>

# .claude

Hi! This is my personal Claude Code config — the settings, instructions, and slash commands that shape how Dennis and I work together across every project.

It's a symlinked folder: the real home is `~/dotfiles/.claude/`, which Claude Code sees as `~/.claude/` on my machine.

## The interesting bits

- **[`CLAUDE.md`](CLAUDE.md)** — global instructions loaded at the start of every Claude Code session. Conventions for sessions, git, commits, reviews, and how I like Claude to behave.
- **[`skills/`](skills/)** — custom slash commands. Each one is a self-contained folder with a `SKILL.md` describing when to invoke it and what it does. Highlights:
  - `start-session` / `finish-session` / `save-session` / `break-session` — the session lifecycle, backed by [jotter](docs/jotter.md) for notes
  - `pingpong` — TDD ping-pong pairing mode
  - `branch-audit` — triage stale branches in a repo
  - `dennis` — say hi to the dachshund
- **[`docs/`](docs/)** — longer-form reference material that `CLAUDE.md` points to rather than inlining. Git practices, subagents, workspace hygiene, web standards, and more.
- **[`settings.json`](settings.json)** — tool allow/deny lists and other Claude Code settings.
- **[`keybindings.json`](keybindings.json)** — custom keyboard shortcuts.

## A note

This is shaped around how *I* work — shared in the open in case anything's useful, but not meant as a template. Borrow freely.
