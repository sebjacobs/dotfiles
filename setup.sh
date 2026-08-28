#!/usr/bin/env sh

DOTFILES_HOME="$(cd "$(dirname "$0")" && pwd)"

# Ensure ~/dotfiles always points here (paths in .zshrc are hardcoded to ~/dotfiles)
if [ "$DOTFILES_HOME" != "$HOME/dotfiles" ]; then
  ln -snf "$DOTFILES_HOME" "$HOME/dotfiles"
  echo "symlinked ~/dotfiles -> $DOTFILES_HOME"
fi

source $DOTFILES_HOME/zsh/00_brew.zsh

if ! command -v brew &> /dev/null; then
  echo "please install homebrew"
  exit
fi

if ! command -v rpup > /dev/null; then
  echo "please install rpup (go install github.com/sebjacobs/rpup@latest)"
  exit
fi

if ! command -v volta > /dev/null; then
  echo "please install volta"
  exit
fi

if ! command -v starship > /dev/null; then
  echo "please install starship (brew install starship)"
  exit
fi

# Soft checks: dependencies installed manually (outside brew bundle / the hard
# prerequisites above). They are not required for symlinking to succeed, so warn
# and keep going rather than exit. Install commands live in CLAUDE.md's
# "Manual steps after setup" section. Each test probes the artefact directly
# (dir/file/binary) rather than a PATH command, since several are shell
# functions or live under $HOME and aren't on a fresh sh's PATH.
missing_manual=0
warn_manual() {
  # $1 = human hint (name + install command)
  echo "  ⚠ missing: $1"
  missing_manual=$((missing_manual + 1))
}

echo "checking manually-installed dependencies:"
[ -x "$HOME/.cargo/bin/cargo" ] || command -v cargo > /dev/null \
  || warn_manual "rust toolchain (curl https://sh.rustup.rs -sSf | sh)"
[ -d "$HOME/.sdkman" ] \
  || warn_manual "sdkman + java (see https://sdkman.io, then sdk install java 21.0.7-tem)"
ls "$HOME"/.rubies/*/bin/ruby > /dev/null 2>&1 \
  || warn_manual "a ruby build (ruby-install ruby 4.0.5 && rpup use ruby-4.0.5) — rpup needs one"
[ -d "$HOME/Library/Android/sdk" ] \
  || warn_manual "Android SDK (\$ANDROID_HOME) — install via Android Studio's SDK Manager"
command -v claude > /dev/null \
  || warn_manual "Claude Code CLI (npm install -g @anthropic-ai/claude-code)"
[ -f "$HOME/.secrets.zsh" ] \
  || warn_manual "~/.secrets.zsh (create from backup — never committed)"
ls "$HOME"/.ssh/id_* > /dev/null 2>&1 \
  || warn_manual "ssh key (ssh-keygen -t ed25519 -C \"<your-email>\")"

if [ "$missing_manual" -eq 0 ]; then
  echo "  all manual dependencies present"
fi

dirs=(
  ".bundle"
  ".claude"
  ".config/dot"
  ".config/opencode"
  ".config/helix"
  "Library/LaunchAgents"
)

for dir in "${dirs[@]}"
do
  mkdir -p "$HOME/$dir"
done

files=(
  ".zshrc"
  ".zshenv"
  ".bundle/config"
  ".ssh/config"
  ".editorconfig"
  ".gemrc"
  ".gitattributes"
  ".gitconfig"
  ".gitignore"
  ".gwt.yml"
  ".ruby-version"
  ".jotter"
  ".claude/CLAUDE.md"
  ".claude/settings.json"
  ".claude/statusline.sh"
  ".claude/keybindings.json"
  ".claude/skills"
  ".claude/agents"
  ".claude/docs"
  ".config/starship.toml"
  ".config/dot/tools.yml"
  ".config/opencode/opencode.json"
  ".config/opencode/package.json"
  ".config/opencode/package-lock.json"
  ".config/opencode/bun.lock"
  ".config/helix/config.toml"
)

for file in "${files[@]}"
do
  source="$DOTFILES_HOME/$file"
  target="$HOME/$file"
  if [ -f $target ] || [ -d $target ]; then
      if ! test -L $target; then
        echo "skipping $target"
      fi
  else
    ln -snf $source $target
  fi
done


for file in $(ls "$DOTFILES_HOME/bin")
do
  source="$DOTFILES_HOME/bin/$file"
  target="$HOME/bin/$file"
  ln -snf $source $target
done

# proj manifest: declares which dirs under $PROJ_ROOT are project categories
# (see lib/proj.rb). Symlinked into $PROJ_ROOT (default ~/Tech/Projects) so a
# fresh checkout knows the taxonomy before any project dir is cloned.
proj_root="${PROJ_ROOT:-$HOME/Tech/Projects}"
mkdir -p "$proj_root"
ln -snf "$DOTFILES_HOME/proj/projroot" "$proj_root/.projroot"

# launchd agents: symlink every repo-managed $LAUNCHD_PREFIX.* plist into
# ~/Library/LaunchAgents and (re)load it, so a fresh checkout brings the agents
# up without a re-login. Globbing the prefix rather than naming files means a new
# agent is picked up just by dropping its plist into Library/LaunchAgents/ here.
# Done in sh rather than `svc install` because setup runs before a modern Ruby is
# guaranteed, and svc (Ruby 3+ syntax) may not run yet at this point.
PREFIX="${LAUNCHD_PREFIX:-com.sebjacobs}"
for plist in "$DOTFILES_HOME"/Library/LaunchAgents/"$PREFIX".*.plist
do
  [ -e "$plist" ] || continue
  target="$HOME/Library/LaunchAgents/$(basename "$plist")"
  ln -snf "$plist" "$target"
  label="$(basename "$plist" .plist)"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
  launchctl bootstrap "gui/$(id -u)" "$target" 2>/dev/null || true
done

# iTerm2: the display-font run below renders iterm2/seb.template.json into
# iTerm's DynamicProfiles folder (generated, not symlinked, so the font size
# isn't tracked). Point iTerm at that profile as the default; iTerm hot-reloads
# the folder, so the render applies without a restart.
if [ -d "$HOME/Library/Application Support/iTerm2" ]; then
  defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "SEB-MAIN-DYNAMIC-PROFILE"

  # iTerm global (non-profile) settings. Profiles are versioned as dynamic
  # profiles, but these app-wide tweaks live only in the prefs plist, so
  # capture them here as declarative `defaults write` lines. Applied on the
  # next iTerm launch; quit iTerm before re-running setup or it may write its
  # in-memory state back over these on quit.

  # Custom mouse gestures: 3-finger swipe = prev/next tab (left/right) and
  # window (up/down); middle-click pastes; ctrl-click opens the context menu.
  defaults write com.googlecode.iterm2 PointerActions -dict \
    'Gesture,ThreeFingerSwipeDown,,'  '{ Action = kPrevWindowPointerAction; }' \
    'Gesture,ThreeFingerSwipeUp,,'    '{ Action = kNextWindowPointerAction; }' \
    'Gesture,ThreeFingerSwipeLeft,,'  '{ Action = kPrevTabPointerAction; }' \
    'Gesture,ThreeFingerSwipeRight,,' '{ Action = kNextTabPointerAction; }' \
    'Button,1,1,,'                    '{ Action = kContextMenuPointerAction; }' \
    'Button,2,1,,'                    '{ Action = kPasteFromClipboardPointerAction; }'

  # Key handling: repeat on hold (vim-friendly), and no Esc feedback.
  defaults write com.googlecode.iterm2 ApplePressAndHoldEnabled -bool false
  defaults write com.googlecode.iterm2 HapticFeedbackForEsc -bool false
  defaults write com.googlecode.iterm2 SoundForEsc -bool false
  defaults write com.googlecode.iterm2 VisualIndicatorForEsc -bool false
  defaults write com.googlecode.iterm2 PreventEscapeSequenceFromClearingHistory -bool false

  # Behaviour + appearance.
  defaults write com.googlecode.iterm2 AllowClipboardAccess -bool true
  defaults write com.googlecode.iterm2 ShowFullScreenTabBar -bool false
  defaults write com.googlecode.iterm2 "Print In Black And White" -bool true
  defaults write com.googlecode.iterm2 PasteTabToStringTabStopSize -int 4

  # AI integration (the API key itself lives in the keychain, not here).
  defaults write com.googlecode.iterm2 EnableAPIServer -bool true
  defaults write com.googlecode.iterm2 AITermAPI -int 2
  defaults write com.googlecode.iterm2 AiModel -string 'gpt-5.5'
  defaults write com.googlecode.iterm2 AitermURL -string 'https://api.openai.com/v1/responses'
fi

# Ghostty: everything else lives in ghostty/config.template (rendered by the
# display-font run below). Key repeat on hold is the one setting that isn't a
# config key — it's the AppKit-wide NSUserDefault, same as iTerm's above.
if [ -d "/Applications/Ghostty.app" ]; then
  defaults write com.mitchellh.ghostty ApplePressAndHoldEnabled -bool false
fi

# display-font: render the generated app configs (Zed settings, iTerm profile,
# Ghostty config) from their tracked templates for the currently-connected
# display. Seeds ~/.config/zed/settings.json, iTerm's dynamic profile and
# ~/.config/ghostty/config — all generated, not symlinked — so a fresh checkout
# has working configs at the right size.
DOTFILES_HOME="$DOTFILES_HOME" "$DOTFILES_HOME/bin/display-font" || true

# SDKMAN runs compinit and a chpwd hook on every shell that sources sdkman-init.sh
# — non-interactive ones included, since it's pulled in from .zshenv via
# zsh/env.zsh. Defer its two auto_* flags to a pre-set value so env.zsh can force
# them off for non-interactive shells without losing the interactive defaults.
# Idempotent: the plain `=true`/`=false` lines only match before the first patch
# (sdkman rewrites the config on selfupdate, so re-running setup re-applies it).
sdkman_config="$HOME/.sdkman/etc/config"
if [ -f "$sdkman_config" ] && grep -q '^sdkman_auto_complete=true$' "$sdkman_config"; then
  sed -e 's/^sdkman_auto_complete=true$/sdkman_auto_complete="${sdkman_auto_complete:-true}"/' \
      -e 's/^sdkman_auto_env=false$/sdkman_auto_env="${sdkman_auto_env:-false}"/' \
      "$sdkman_config" > "$sdkman_config.tmp" && mv "$sdkman_config.tmp" "$sdkman_config"
  echo "patched sdkman config to defer auto_complete/auto_env to the environment"
fi

# Clear the zsh completion cache so a completion that was just (re)symlinked onto
# $fpath is picked up by the next shell rather than hidden behind a stale
# ~/.zcompdump. Done here in sh to keep setup dependency-free (it may run before a
# modern Ruby is on PATH). Start a new shell afterwards to rebuild the cache.
rm -f "$HOME"/.zcompdump*

echo "finished symlinking dotfiles"
