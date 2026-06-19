# Environment — also loaded by ~/.zshenv for non-interactive shells. Re-sourced
# here so PATH wins over /etc/zprofile's path_helper in login shells.
source ~/dotfiles/zsh/env.zsh

# Completions (must be on fpath before compinit runs)
fpath=(~/dotfiles/zsh/completions $fpath)

# Plugins
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Per-directory ruby switching + direnv (interactive only)
source /opt/homebrew/opt/chruby/share/chruby/auto.sh
eval "$(direnv hook zsh)"

source ~/dotfiles/zsh/aliases.zsh
source ~/dotfiles/zsh/git_aliases.zsh
source ~/dotfiles/zsh/gwt.zsh
source ~/dotfiles/zsh/projects.zsh

# Secrets (gitignored)
[ -f ~/.secrets.zsh ] && source ~/.secrets.zsh

# Prompt
eval "$(starship init zsh)"
