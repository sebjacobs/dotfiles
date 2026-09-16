typeset -U path PATH fpath

source ~/dotfiles/zsh/00_brew.zsh

# brew's shellenv rebuilds PATH via path_helper, which yields only Homebrew dirs
# when PATH started empty (cold cron/launchd). Re-add the system base so system
# tools and coreutils resolve; typeset -U dedupes and appending keeps Homebrew first.
path+=(/usr/bin /bin /usr/sbin /sbin)

export DYLD_LIBRARY_PATH="/opt/homebrew/lib"

export EDITOR='hx'
export VISUAL='zed --wait'

export LAUNCHD_PREFIX="com.sebjacobs"

# rpup (github.com/sebjacobs/rpup) lives in go's bin dir and must be on PATH
# before its hook runs below, so add go's bin here rather than further down.
export PATH="$HOME/go/bin:$PATH"

# Ruby version management via rpup, a fork-free chruby replacement. Its hook
# reads the default from ~/.ruby-version (symlinked to the repo's copy by
# setup.sh), activates it, and wires per-directory switching on chpwd — one line
# serving every shell, with no ruby spawn and no split interactive/
# non-interactive paths.
#
# Clear the per-directory guard first so the hook re-activates on every source,
# not just the first: /etc/zprofile's path_helper reshuffles PATH between
# .zshenv and .zshrc's re-source (see .zshrc), pushing system ruby ahead of
# rpup's bins, and only a fresh activation puts them back. Guarded on the binary
# so a missing rpup degrades to system ruby rather than erroring shell init.
unset RPUP_CURRENT_VERSION
command -v rpup >/dev/null && eval "$(rpup hook zsh)"

export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"
unset _VOLTA_TOOL_RECURSION

export PATH="$HOME/.opencode/bin:$PATH"
export PATH="$PATH:$HOME/.lmstudio/bin"

# postgresql@18 is keg-only, so its client tools (psql, pg_dump, ...) aren't
# linked onto PATH by brew. Add the bin dir explicitly; the server stays
# dormant unless `brew services start` is run.
export PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH"

export OLLAMA_KEEP_ALIVE=-1

# dox (github.com/sebjacobs/dox) defaults to the docker backend; opt this machine
# into the experimental apple-container backend globally. A project .env can still
# override per-project. Until dox grows a global config layer (see its docs/backlog.md).
export DOX_BACKEND=container

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
  # candidate bins and their *_HOME vars on the environment directly.
  # java/gradle/kotlin/maven stay resolvable — and win over the /usr/bin/java
  # stub — for only the cost of a glob; the init script and its completion scan
  # are shed entirely.
  for _sdkman_home in "$SDKMAN_DIR"/candidates/*/current(N-/); do
    path=("$_sdkman_home/bin" $path)
    _sdkman_name=${_sdkman_home:h:t}
    export "${(U)_sdkman_name}_HOME"="$_sdkman_home"
  done
  unset _sdkman_home _sdkman_name
fi

export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator

export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1

# rustup's ~/.cargo/env only prepends .cargo/bin when it's absent, so on .zshrc's
# re-source (after /etc/zprofile's path_helper reshuffles PATH) it no-ops and
# Homebrew's bin shadows the shims. Prepend unconditionally instead; typeset -U
# dedupes. Stays below the personal bins added next so ~/bin still wins.
path=("$HOME/.cargo/bin" $path)

# ~/.local/bin then ~/bin prepended last so personal scripts/shims win over
# language-managed bins and macOS path_helper reordering in login shells.
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/bin:$PATH"

export PATH="$HOME/Tech/Projects/open-source/depot_tools:$PATH"

# The home server's helper scripts: slopz, deploy, push-media. Appended so
# nothing there can shadow a personal shim.
path+=("$HOME/Tech/Projects/personal/slopz-box/bin")
