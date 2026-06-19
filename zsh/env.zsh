typeset -U path PATH

source ~/dotfiles/zsh/00_brew.zsh

export EDITOR='zed --wait'

source /opt/homebrew/opt/chruby/share/chruby/chruby.sh
CHRUBY_VERSION=ruby-4.0.5
chruby "$CHRUBY_VERSION"

export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"
unset _VOLTA_TOOL_RECURSION

export PATH="$HOME/go/bin:$PATH"

export PATH="$HOME/.opencode/bin:$PATH"
export PATH="$PATH:$HOME/.lmstudio/bin"

export OLLAMA_KEEP_ALIVE=-1

export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# ~/.local/bin then ~/bin prepended last so personal scripts/shims win over
# language-managed bins and macOS path_helper reordering in login shells.
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/bin:$PATH"
