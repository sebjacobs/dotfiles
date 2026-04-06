# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Key constraint

`.claude/CLAUDE.md` is symlinked to `~/.claude/CLAUDE.md`. Changes to it must be committed here in the dotfiles repo — editing the symlink target directly won't track in git.

## Bootstrap & installation

```bash
./setup.sh          # Creates all symlinks into $HOME; idempotent
brew bundle         # Install/sync all packages from Brewfile
./bin/dotfiles-init # Wrapper for setup.sh — equivalent
```

`setup.sh` requires Homebrew, Chruby, Volta, and Starship to already be installed. It creates symlinks for dotfiles and all scripts under `bin/` into `~/bin/`.

## Architecture

**Symlink-based:** `setup.sh` symlinks individual files from this repo into `$HOME`. Nothing is copied — edits to `~/dotfiles/<file>` are the same as editing `~/<file>`.

**Managed locations:**
- `./` — dotfiles (`.gitconfig`, `.editorconfig`, etc.) → symlinked to `$HOME`
- `zsh/` — shell environment, PATH, aliases, git shortcuts → sourced directly from `~/.zshrc`
- `.claude/` — Claude Code settings, keybindings, and global Claude config → symlinked to `~/.claude/`:
  - `CLAUDE.md` — always loaded at session start; principles and rules, kept concise
  - `skills/` — auto-discovered slash commands available in all projects
  - `agents/` — named subagents invokable via the Agent tool
  - `docs/` — longer reference material (not auto-loaded; CLAUDE.md points to these by path)
- `bin/` — shell utilities → symlinked into `~/bin/`
- `Brewfile` — full tool inventory (Homebrew formulae, casks, Go/Rust/Python/NPM packages)

**Shell init load order:** `~/.zshrc` → `zsh/00_brew.zsh` (Homebrew env) → `zsh/01_env.zsh` (PATH: PostgreSQL, MySQL, Volta, Go, Chruby, sdkman) → `zsh/git_aliases.zsh` + `zsh/aliases.zsh` → `~/.secrets.zsh` → Starship prompt

**Tool versions:** Ruby via Chruby (`.ruby-version` in project dirs), Node via Volta, Python via `uv`, Go and Rust via Homebrew, Java via sdkman.

## Claude Code config

`~/.claude/settings.json` whitelists specific tools only — notably `git push` is **not** in the allow-list (requires explicit user approval each time). The deny-list blocks `rm -rf`, `sudo`, and credential paths (`~/.ssh/**`, `~/.aws/**`).
