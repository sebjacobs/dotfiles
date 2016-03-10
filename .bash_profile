#chruby setup
source /usr/local/opt/chruby/share/chruby/chruby.sh
chruby ruby-2.3.0

#vim setup
export EDITOR="vim"

#path additions
export PATH=.bundle/bin:$PATH
export PATH=/usr/local/bin:$PATH

#bundler aliases
alias be="bundle exec"
alias bi="bundle install"
alias bu="bundle update"

#git aliases
alias git=hub
alias gst="git status"
alias gco="git checkout"
alias gfe="git fetch"
alias grom="git rebase origin/master"
alias grim="git rebase -i origin/master"
alias gl="git l"
alias gla="git la"
alias gad="git add ."
alias gam="git commit --amend"
alias gcon="git rebase --continue"

#git scripts
source ~/scripts/git-completion.sh
source ~/scripts/git-prompt.sh

PS1='[\u@\h \W$(__git_ps1 " (%s)")]\$ '

#profile secrets
source ~/.profile_secrets

function flssh {
  local environment=$1
  local username=$2

  bundle exec cap $environment ec2:status
  read -p "Please enter the server Num you wish to connect to: " server_id

  local dns_name=$(bundle exec cap $environment ec2:status | grep "^\s$server_id" | awk '{print $5}')

  [ -z "$username" ] && username='futurelearn'

  ssh "$username@$dns_name"
}

export GREP_OPTIONS='--color=auto --exclude-dir=.bundle --exclude-dir=.git'
