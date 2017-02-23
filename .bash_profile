#vim setup
export EDITOR="vim"

#path additions
export PATH=.bundle/bin:$PATH
export PATH=/usr/local/sbin:$PATH
export PATH=/usr/local/bin:$PATH
export PATH=./bin:$PATH
export PATH=$PATH:/usr/local/opt/go/libexec/bin

export JAVA_HOME="$(/usr/libexec/java_home)"

#chruby setup
source /usr/local/opt/chruby/share/chruby/chruby.sh
chruby ruby-2.3.3

#bundler aliases
alias be="bundle exec"
alias bi="bundle install"
alias bu="bundle update"

#rails aliases
alias mig="bundle exec rake db:migrate"
alias s="bundle exec rails s"
alias c="bundle exec rails c"

#ruby variables
export RUBY_GC_HEAP_INIT_SLOTS=1000000
export RUBY_HEAP_SLOTS_INCREMENT=1000000
export RUBY_HEAP_SLOTS_GROWTH_FACTOR=1
export RUBY_GC_MALLOC_LIMIT=100000000
export RUBY_HEAP_FREE_MIN=500000

#git scripts
source ~/scripts/git-completion.sh
source ~/scripts/git-prompt.sh

#git aliases
source ~/.git_aliases

PS1='[\u@\h \W$(__git_ps1 " (%s)")]\$ '

export GREP_OPTIONS='--color=auto --exclude-dir=.bundle --exclude-dir=.git'

source ~/.profile-secrets

