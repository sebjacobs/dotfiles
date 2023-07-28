# ruby/rails
alias bi="bundle install"
alias be="bundle exec"
alias mig="bundle exec rake db:migrate"
alias ffs="bundle install && yarn install && bundle exec rails db:migrate"

# python/django
alias pyman="poetry run python manage.py"
alias pyt="poetry run pytest"

# nodejs
alias node-init="rsync -r --exclude=\"package-lock.json\" --exclude=\"dist\" --exclude=\".git\" --exclude \"node_modules\"  ~/Tech/Projects/templates/nodejs-template/* $1"
alias express-init="rsync -r --exclude=\"package-lock.json\" --exclude=\"dist\" --exclude=\".git\" --exclude \"node_modules\"  ~/Tech/Projects/templates/express-template/* $1"


alias intel="env /usr/bin/arch -x86_64 /bin/zsh"
alias arm="env /usr/bin/arch -arm64 /bin/zsh"

function convert_ac3_to_aac() {
  filename=$1
  extension="${filename##*.}"
  filename="${filename%.*}"
  output_filename="$filename-aac.$extension"

  # ffmpeg -i $1 -vcodec copy -scodec copy -acodec libfdk_aac -b:a 640k -ac 6 -map 0 $output_filename
  ffmpeg -i $1 -vcodec copy -scodec copy -acodec libfdk_aac -b:a 640k -ac 6 -map 0:a -map 0:v -map 0:s:m:language:eng $output_filename
}

alias ac3_to_aac="convert_ac3_to_aac"