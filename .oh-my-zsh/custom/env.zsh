eval "$(/opt/homebrew/bin/brew shellenv)"

#export JAVA_HOME=$(/usr/libexec/java_home -v 11)
#export JAVA_HOME=$(/usr/libexec/java_home -v 17)
#export JAVA_HOME=$(/usr/libexec/java_home -v 16)
export JAVA_HOME=$(/usr/libexec/java_home -v 20)
#export PATH="$HOME/.jenv/bin:$PATH"
#eval "$(jenv init -)"

export ANDROID_HOME=~/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/tools/bin
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=$PATH:$HOME/bin


export PATH="/opt/homebrew/opt/openssl@1.1/bin:$PATH"
export LDFLAGS="-L/opt/homebrew/opt/openssl@1.1/lib"
export CPPFLAGS="-I/opt/homebrew/opt/openssl@1.1/include"

#export RUBY_CONFIGURE_OPTS="--with-zlib-dir=$(brew --prefix zlib) --with-openssl-dir=$(brew --prefix openssl@1.1) --with-readline-dir=$(brew --prefix readline) --with-libyaml-dir=$(brew --prefix libyaml)"

export DENO_INSTALL="/Users/sebjacobs/.deno"
export PATH="$DENO_INSTALL/bin:$PATH"

export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# python poetry setup
export PIP_REQUIRE_VIRTUAL_ENV=true
export PATH="/Users/sebjacobs/.local/bin:$PATH"

export PATH="/opt/homebrew/opt/dotnet@6/bin:$PATH"
export DOTNET_ROOT="/opt/homebrew/opt/dotnet@6/libexec"

export PATH="$PATH":"$HOME/.pub-cache/bin"

export EDITOR='code --wait'

source /opt/homebrew/opt/chruby/share/chruby/chruby.sh
# chruby 3.2.1
chruby 2.7.7

export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion
nvm use --lts
