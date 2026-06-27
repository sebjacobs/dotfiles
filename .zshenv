# ${(%):-%x} is this file's own path; :A resolves the ~ symlink setup.sh
# installs back to the repo, so the dotfiles boot from any checkout location.
source "${${(%):-%x}:A:h}/zsh/env.zsh"
