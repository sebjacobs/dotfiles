source "/Users/sebjacobs/.sdkman/bin/sdkman-init.sh"

export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/tools/bin
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=$PATH:$HOME/bin

if command -v colima &> /dev/null; then
  export DOCKER_HOST=$(docker context inspect colima -f '{{.Endpoints.docker.Host}}')
fi

#export PATH="$BREW_PREFIX/opt/openssl@1.1/bin:$PATH"
#export LDFLAGS="-L$BREW_PREFIX/opt/openssl@1.1/lib"
#export CPPFLAGS="-I$BREW_PREFIX/opt/openssl@1.1/include"

#export RUBY_CONFIGURE_OPTS="--with-zlib-dir=$(brew --prefix zlib) --with-openssl-dir=$(brew --prefix openssl@1.1) --with-readline-dir=$(brew --prefix readline) --with-libyaml-dir=$(brew --prefix libyaml)"

export DENO_INSTALL="$HOME/.deno"
export PATH="$DENO_INSTALL/bin:$PATH"

export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# python poetry setup
export PIP_REQUIRE_VIRTUAL_ENV=true
export PATH="$HOME/.local/bin:$PATH"

#dotnet setup
export PATH="$PATH:$HOME/.dotnet/tools"

export PATH="$PATH":"$HOME/.pub-cache/bin"

export EDITOR='code --wait'

## Ruby version management
. $BREW_PREFIX/opt/asdf/libexec/asdf.sh

## NodeJS version management
export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

#golang
export PATH="$HOME/go/bin:$PATH"

# setup kubectl autocompletion
source <(kubectl completion zsh)


