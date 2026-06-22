typeset -U path PATH fpath

source ~/dotfiles/zsh/00_brew.zsh

# brew's shellenv rebuilds PATH via path_helper, which yields only Homebrew dirs
# when PATH started empty (cold cron/launchd). Re-add the system base so chruby
# and coreutils resolve; typeset -U dedupes and appending keeps Homebrew first.
path+=(/usr/bin /bin /usr/sbin /sbin)

export EDITOR='zed --wait'

DEFAULT_RUBY=ruby-4.0.5
if [[ -o interactive ]]; then
  source /opt/homebrew/opt/chruby/share/chruby/chruby.sh
  chruby "$DEFAULT_RUBY"
  # chruby silently no-ops if its RUBIES glob is empty during a transient init
  # (seen in Claude Code shell-snapshot capture): ruby then never lands on PATH
  # and `ruby` falls through to system 2.6. Assert the chosen bin dir directly.
  [[ -d "$HOME/.rubies/$DEFAULT_RUBY/bin" ]] && path=("$HOME/.rubies/$DEFAULT_RUBY/bin" $path)
else
  # chruby's switch spawns `ruby` once just to read the gem paths — ~40ms a
  # shell. Those paths are deterministic from DEFAULT_RUBY, so for
  # non-interactive shells set the same environment chruby would (RUBY_ROOT,
  # GEM_HOME, GEM_PATH, PATH) without the spawn or the function machinery the
  # interactive `chruby`/`ruby-version` commands need. gem/bundler behave
  # identically; only the startup cost is shed.
  ruby_root="$HOME/.rubies/$DEFAULT_RUBY"
  if [[ -d "$ruby_root/bin" ]]; then
    export RUBY_ROOT="$ruby_root"
    export RUBY_ENGINE=ruby
    export RUBY_VERSION="${DEFAULT_RUBY#ruby-}"
    gem_root=("$ruby_root"/lib/ruby/gems/*(N/))
    export GEM_ROOT="${gem_root[1]}"
    export GEM_HOME="$HOME/.gem/$RUBY_ENGINE/$RUBY_VERSION"
    export GEM_PATH="$GEM_HOME:$GEM_ROOT"
    export PATH="$GEM_HOME/bin:$GEM_ROOT/bin:$ruby_root/bin:$PATH"
  fi
  unset ruby_root gem_root
fi

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

export SDKMAN_DIR="$HOME/.sdkman"
if [[ -o interactive ]]; then
  [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
else
  # sdkman-init.sh runs compinit and registers a chpwd hook every time it is
  # sourced (~50ms a shell) — all interactive-only machinery a `zsh -c` never
  # touches. Skip it for non-interactive shells and instead put the active
  # candidate bins and their *_HOME vars on the environment directly, the same
  # way chruby's bin dir is asserted above. java/gradle/kotlin/maven stay
  # resolvable — and win over the /usr/bin/java stub — for only the cost of a
  # glob; the init script and its completion scan are shed entirely.
  for _sdkman_home in "$SDKMAN_DIR"/candidates/*/current(N-/); do
    path=("$_sdkman_home/bin" $path)
    _sdkman_name=${_sdkman_home:h:t}
    export "${(U)_sdkman_name}_HOME"="$_sdkman_home"
  done
  unset _sdkman_home _sdkman_name
fi

export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# ~/.local/bin then ~/bin prepended last so personal scripts/shims win over
# language-managed bins and macOS path_helper reordering in login shells.
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/bin:$PATH"
