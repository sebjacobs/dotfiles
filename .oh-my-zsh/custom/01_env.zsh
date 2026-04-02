export PATH=$PATH:$HOME/bin
export PATH="$HOME/.local/bin:$PATH"

export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
export PATH="/opt/homebrew/opt/mysql@8.4/bin:$PATH"

export LDFLAGS="-L/opt/homebrew/opt/mysql@8.4/lib"
export CPPFLAGS="-I/opt/homebrew/opt/mysql@8.4/include"

export DENO_INSTALL="$HOME/.deno"
export PATH="$DENO_INSTALL/bin:$PATH"

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

