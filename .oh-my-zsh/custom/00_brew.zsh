if test -d "/opt/homebrew"; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  export BREW_PREFIX=/opt/homebrew
else
  eval "$(/usr/local/bin/brew shellenv)"
  export BREW_PREFIX=/usr/local
fi

