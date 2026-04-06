#!/usr/bin/env sh

DOTFILES_HOME=$HOME/dotfiles

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
)

for dir in "${dirs[@]}"
do
  mkdir -p "$HOME/$dir"
done

files=(
  ".bundle/config"
  ".ssh/config"
  ".editorconfig"
  ".gemrc"
  ".gitattributes"
  ".gitconfig"
  ".gitignore"
  ".claude/CLAUDE.md"
  ".claude/settings.json"
  ".claude/keybindings.json"
  ".claude/skills"
  ".claude/agents"
  ".claude/docs"
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

echo "finished symlinking dotfiles"
