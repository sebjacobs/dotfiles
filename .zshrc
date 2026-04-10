# Config
source ~/dotfiles/zsh/00_brew.zsh

# Plugins
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source ~/dotfiles/zsh/01_env.zsh
source ~/dotfiles/zsh/aliases.zsh
source ~/dotfiles/zsh/git_aliases.zsh
source ~/dotfiles/zsh/worktree.zsh

# Secrets (gitignored)
[ -f ~/.secrets.zsh ] && source ~/.secrets.zsh

# Misc PATH
export PATH=$HOME/.opencode/bin:$PATH
export PATH="$PATH:$HOME/.lmstudio/bin"

# Prompt
eval "$(starship init zsh)"
