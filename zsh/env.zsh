typeset -U path PATH fpath

source ~/dotfiles/zsh/00_brew.zsh

# brew's shellenv rebuilds PATH via path_helper, which yields only Homebrew dirs
# when PATH started empty (cold cron/launchd). Re-add the system base so chruby
# and coreutils resolve; typeset -U dedupes and appending keeps Homebrew first.
path+=(/usr/bin /bin /usr/sbin /sbin)

export EDITOR='zed --wait'

source /opt/homebrew/opt/chruby/share/chruby/chruby.sh
CHRUBY_VERSION=ruby-4.0.5
chruby "$CHRUBY_VERSION"
# chruby silently no-ops if its RUBIES glob is empty during a transient init
# (seen in Claude Code shell-snapshot capture): ruby then never lands on PATH
# and `ruby` falls through to system 2.6. Assert the chosen bin dir directly.
[[ -d "$HOME/.rubies/$CHRUBY_VERSION/bin" ]] && path=("$HOME/.rubies/$CHRUBY_VERSION/bin" $path)

export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"
unset _VOLTA_TOOL_RECURSION

export PATH="$HOME/go/bin:$PATH"

export PATH="$HOME/.opencode/bin:$PATH"
export PATH="$PATH:$HOME/.lmstudio/bin"

# postgresql@18 is keg-only, so its client tools (psql, pg_dump, ...) aren't
# linked onto PATH by brew. Add the bin dir explicitly; the server stays
# dormant unless `brew services start` is run.
export PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH"

export OLLAMA_KEEP_ALIVE=-1

# Completion dirs must be on fpath before SDKMAN's init runs compinit (below) —
# .zshrc loads only after .zshenv, so setting them there is too late and new
# completions go undiscovered. The local site-functions dir holds completions
# installed outside dotfiles (e.g. `rake install` targets).
fpath=(~/dotfiles/zsh/completions ~/.local/share/zsh/site-functions $fpath)

# SDKMAN runs compinit and registers a chpwd hook on every shell that sources it,
# this file included — so a plain `zsh -c` pays a full completion scan it never
# uses. Both are interactive-only concerns; force them off for non-interactive
# shells. etc/config defers to a pre-set value (the `${var:-default}` form), so
# interactive shells leave these unset and keep SDKMAN's configured defaults.
if [[ ! -o interactive ]]; then
  sdkman_auto_complete=false
  sdkman_auto_env=false
fi

export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# ~/.local/bin then ~/bin prepended last so personal scripts/shims win over
# language-managed bins and macOS path_helper reordering in login shells.
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/bin:$PATH"
