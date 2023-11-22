#!/usr/bin/env sh

source ./.oh-my-zsh/custom/00_brew.zsh

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "please install oh-my-zsh"
  exit
fi

if ! grep "^ZSH_CUSTOM" ~/.zshrc > /dev/null; then
  awk '1;/# ZSH_CUSTOM/{print "ZSH_CUSTOM=$HOME/dotfiles/.oh-my-zsh/custom"}' $HOME/.zshrc > $HOME/.zshrc.tmp && mv $HOME/.zshrc.tmp $HOME/.zshrc
fi

if ! command -v brew &> /dev/null; then
  echo "please install homebrew"
  exit
fi

if ! command -v pyenv >/dev/null; then
  echo "please install pyenv"
  exit
fi

if ! test -f "$BREW_PREFIX/opt/asdf/libexec/asdf.sh"; then
  echo "please install asdf"
  exit
fi

if ! command -v volta > /dev/null; then
  echo "please install volta"
  exit
fi

if ! test -d $HOME/.sdkman; then
  echo "please install sdkman"
  exit
fi

dirs=(
  ".bundle"
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
)

for file in "${files[@]}"
do
  source="$(pwd)/$file"
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
  source="$(pwd)/bin/$file"
  target="$HOME/bin/$file"
  ln -snf $source $target
done

echo "finished symlinking dotfiles"
