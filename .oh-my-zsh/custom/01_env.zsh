#export JAVA_HOME=$(/usr/libexec/java_home -v 11)
#export JAVA_HOME=$(/usr/libexec/java_home -v 17)
#export JAVA_HOME=$(/usr/libexec/java_home -v 16)
export JAVA_HOME=$(/usr/libexec/java_home -v 20)
#export PATH="$HOME/.jenv/bin:$PATH"
#eval "$(jenv init -)"

export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/tools/bin
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=$PATH:$HOME/bin


export PATH="$BREW_PREFIX/opt/openssl@1.1/bin:$PATH"
export LDFLAGS="-L$BREW_PREFIX/opt/openssl@1.1/lib"
export CPPFLAGS="-I$BREW_PREFIX/opt/openssl@1.1/include"

#export RUBY_CONFIGURE_OPTS="--with-zlib-dir=$(brew --prefix zlib) --with-openssl-dir=$(brew --prefix openssl@1.1) --with-readline-dir=$(brew --prefix readline) --with-libyaml-dir=$(brew --prefix libyaml)"

export DENO_INSTALL="$HOME/.deno"
export PATH="$DENO_INSTALL/bin:$PATH"

export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# python poetry setup
export PIP_REQUIRE_VIRTUAL_ENV=true
export PATH="$HOME/.local/bin:$PATH"

export PATH="$BREW_PREFIX/opt/dotnet@6/bin:$PATH"
export DOTNET_ROOT="$BREW_PREFIX/opt/dotnet@6/libexec"

export PATH="$PATH":"$HOME/.pub-cache/bin"

export EDITOR='code --wait'

source $BREW_PREFIX/opt/chruby/share/chruby/chruby.sh
chruby 3.2.2
# chruby 2.7.8

export NVM_DIR="$HOME/.nvm"
[ -s "$BREW_PREFIX/opt/nvm/nvm.sh" ] && \. "$BREW_PREFIX/opt/nvm/nvm.sh"  # This loads nvm
nvm use --lts


# setup kubectl autocompletion
source <(kubectl completion zsh)

