#!/usr/bin/env sh

DOTFILES_HOME="$(cd "$(dirname "$0")" && pwd)"

# Ensure ~/dotfiles always points here (paths in .zshrc are hardcoded to ~/dotfiles)
if [ "$DOTFILES_HOME" != "$HOME/dotfiles" ]; then
  ln -snf "$DOTFILES_HOME" "$HOME/dotfiles"
  echo "symlinked ~/dotfiles -> $DOTFILES_HOME"
fi

source $DOTFILES_HOME/zsh/00_brew.zsh

if ! command -v brew &> /dev/null; then
  echo "please install homebrew"
  exit
fi

if ! test -f "/opt/homebrew/opt/chruby/share/chruby/chruby.sh"; then
  echo "please install chruby"
  exit
fi

if ! command -v volta > /dev/null; then
  echo "please install volta"
  exit
fi

if ! command -v starship > /dev/null; then
  echo "please install starship (brew install starship)"
  exit
fi

dirs=(
  ".bundle"
  ".claude"
  ".config/opencode"
  ".config/helix"
  "Library/LaunchAgents"
)

for dir in "${dirs[@]}"
do
  mkdir -p "$HOME/$dir"
done

files=(
  ".zshrc"
  ".zshenv"
  ".bundle/config"
  ".ssh/config"
  ".editorconfig"
  ".gemrc"
  ".gitattributes"
  ".gitconfig"
  ".gitignore"
  ".jotter"
  ".claude/CLAUDE.md"
  ".claude/settings.json"
  ".claude/statusline.sh"
  ".claude/keybindings.json"
  ".claude/skills"
  ".claude/agents"
  ".claude/docs"
  ".config/starship.toml"
  ".config/opencode/opencode.json"
  ".config/opencode/package.json"
  ".config/opencode/package-lock.json"
  ".config/opencode/bun.lock"
  ".config/helix/config.toml"
)

for file in "${files[@]}"
do
  source="$DOTFILES_HOME/$file"
  target="$HOME/$file"
  if [ -f $target ] || [ -d $target ]; then
      if ! test -L $target; then
        echo "skipping $target"
      fi
  else
    ln -snf $source $target
  fi
done


for file in $(ls ./bin)
do
  source="$DOTFILES_HOME/bin/$file"
  target="$HOME/bin/$file"
  ln -snf $source $target
done

# launchd agents: symlink every repo-managed $LAUNCHD_PREFIX.* plist into
# ~/Library/LaunchAgents and (re)load it, so a fresh checkout brings the agents
# up without a re-login. Globbing the prefix rather than naming files means a new
# agent is picked up just by dropping its plist into Library/LaunchAgents/ here.
# Done in sh rather than `svc install` because setup runs before a modern Ruby is
# guaranteed, and svc (Ruby 3+ syntax) may not run yet at this point.
PREFIX="${LAUNCHD_PREFIX:-com.sebjacobs}"
for plist in "$DOTFILES_HOME"/Library/LaunchAgents/"$PREFIX".*.plist
do
  [ -e "$plist" ] || continue
  target="$HOME/Library/LaunchAgents/$(basename "$plist")"
  ln -snf "$plist" "$target"
  label="$(basename "$plist" .plist)"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
  launchctl bootstrap "gui/$(id -u)" "$target" 2>/dev/null || true
done

# SDKMAN runs compinit and a chpwd hook on every shell that sources sdkman-init.sh
# — non-interactive ones included, since it's pulled in from .zshenv via
# zsh/env.zsh. Defer its two auto_* flags to a pre-set value so env.zsh can force
# them off for non-interactive shells without losing the interactive defaults.
# Idempotent: the plain `=true`/`=false` lines only match before the first patch
# (sdkman rewrites the config on selfupdate, so re-running setup re-applies it).
sdkman_config="$HOME/.sdkman/etc/config"
if [ -f "$sdkman_config" ] && grep -q '^sdkman_auto_complete=true$' "$sdkman_config"; then
  sed -e 's/^sdkman_auto_complete=true$/sdkman_auto_complete="${sdkman_auto_complete:-true}"/' \
      -e 's/^sdkman_auto_env=false$/sdkman_auto_env="${sdkman_auto_env:-false}"/' \
      "$sdkman_config" > "$sdkman_config.tmp" && mv "$sdkman_config.tmp" "$sdkman_config"
  echo "patched sdkman config to defer auto_complete/auto_env to the environment"
fi

echo "finished symlinking dotfiles"
