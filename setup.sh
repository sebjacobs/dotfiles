#!/usr/bin/env sh

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "please install oh-my-zsh"
  exit
fi

if ! command -v brew &> /dev/null; then
  echo "please install homebrew"
  exit
fi

files=(
  ".bundle/config"
  ".oh-my-zsh/custom"
  ".ssh/config"
  ".editorconfig"
  ".gemrc"
  ".gitattributes"
  ".gitconfig"
  ".gitignore"
)

for file in "${files[@]}"
do
  source="$(pwd)/$file"
  target="$HOME/$file"
  ln -snf $source $target
done

echo "finished symlinking dotfiles"
