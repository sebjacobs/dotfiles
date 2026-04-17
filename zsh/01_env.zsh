export PATH=$PATH:$HOME/bin

export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
export PATH="/opt/homebrew/opt/mysql@8.4/bin:$PATH"

export LDFLAGS="-L/opt/homebrew/opt/mysql@8.4/lib"
export CPPFLAGS="-I/opt/homebrew/opt/mysql@8.4/include"

export EDITOR='zed --wait'

source /opt/homebrew/opt/chruby/share/chruby/chruby.sh
source /opt/homebrew/opt/chruby/share/chruby/auto.sh

chruby ruby-3.4.5

## NodeJS version management
export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"
unset _VOLTA_TOOL_RECURSION

#golang
export PATH="$HOME/go/bin:$PATH"

# User-local binaries take precedence over language-managed bin dirs (go, volta, etc.)
export PATH="$HOME/.local/bin:$PATH"

export OLLAMA_KEEP_ALIVE=-1

## Java version management
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"


export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1

