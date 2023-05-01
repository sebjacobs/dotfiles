alias bi="bundle install"
alias be="bundle exec"
alias mig="bundle exec rake db:migrate"
alias ffs="bundle install && yarn install && bundle exec rails db:migrate"

alias pyman="poetry run python manage.py"

alias intel="env /usr/bin/arch -x86_64 /bin/zsh"
alias arm="env /usr/bin/arch -arm64 /bin/zsh"

function convert_ac3_to_aac() {
  filename=$1
  extension="${filename##*.}"
  filename="${filename%.*}"
  output_filename="$filename-aac.$extension"

  ffmpeg -i $1 -vcodec copy -scodec copy -acodec libfdk_aac -b:a 640k -ac 6 -map 0 $output_filename
}

alias ac3_to_aac="convert_ac3_to_aac"
