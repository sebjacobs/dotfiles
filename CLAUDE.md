# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Key constraint

`.claude/CLAUDE.md` is symlinked to `~/.claude/CLAUDE.md`. Changes to it must be committed here in the dotfiles repo — editing the symlink target directly won't track in git.

## Bootstrap & installation

```bash
# 1. Clone the repo (anywhere — setup.sh creates ~/dotfiles symlink automatically)
git clone git@github.com:sebjacobs/dotfiles.git ~/Tech/Projects/personal/2026/dotfiles
cd ~/Tech/Projects/personal/2026/dotfiles

# 2. Install Xcode CLI tools
xcode-select --install

# 3. Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 4. Install prerequisites
brew install chruby ruby-install volta starship zsh-autosuggestions zsh-syntax-highlighting

# 5. Run setup
./setup.sh          # Creates ~/dotfiles symlink + all $HOME symlinks; idempotent
brew bundle         # Install/sync all packages from Brewfile
```

`setup.sh` requires Homebrew, Chruby, Volta, and Starship to already be installed. It creates a `~/dotfiles` symlink pointing to the repo, then symlinks all config files into `$HOME` and all scripts under `bin/` into `~/bin/`.

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

## Manual steps after setup

Things not covered by `brew bundle` or `setup.sh`:

```bash
# Volta (Node version manager) — install before running setup.sh
curl https://get.volta.sh | bash

# Claude Code CLI
# Download from https://claude.ai/download or install via:
npm install -g @anthropic-ai/claude-code

# Java via sdkman (after brew bundle installs sdkman)
sdk install java 21.0.7-tem
sdk install java 11.0.x-amzn   # for Android

# Ruby
ruby-install ruby 3.4.5
chruby ruby-3.4.5

# Secrets — create manually, never commit
cp /path/to/backup/.secrets.zsh ~/.secrets.zsh
# or recreate: see secrets template in ~/.secrets.zsh structure:
# export GITHUB_USERNAME=...
# export NPM_AUTH_TOKEN=...
# export BUNDLE_RUBYGEMS__PKG__GITHUB__COM=$GITHUB_USERNAME:$NPM_AUTH_TOKEN
# export NODE_AUTH_TOKEN=$NPM_AUTH_TOKEN
# export ANTHROPIC_API_KEY=...

# SSH keys — generate or restore from backup
ssh-keygen -t ed25519 -C "me@sebjacobs.com"
# then add to GitHub: https://github.com/settings/keys
```

## Claude Code config

`~/.claude/settings.json` whitelists specific tools only — notably `git push` is **not** in the allow-list (requires explicit user approval each time). The deny-list blocks `rm -rf`, `sudo`, and credential paths (`~/.ssh/**`, `~/.aws/**`).
