# ruby/rails
alias ba="bundle add"
alias be="bundle exec"
alias bi="bundle install"
alias bu="bundle update"
alias mig="bundle exec rails db:migrate"
alias ffs="bundle install && npm install && bundle exec rails db:migrate"

# python/django
alias pyman="uv run python manage.py"
alias pyt="uv run pytest"

function convert_ac3_to_aac() {
  filename=$1
  extension="${filename##*.}"
  filename="${filename%.*}"
  output_filename="$filename-aac.$extension"

  # remove subtitles and additional audio tracks
  # ffmpeg -i $1 -map 0 -c copy -map -0:a:1 -sn $output_filename
  ffmpeg -i $1 -vcodec copy -scodec copy -acodec libfdk_aac -b:a 640k -ac 6 -map 0 $output_filename
  # copy but remove additional audio tracks
  # ffmpeg -i $1 -vcodec copy -scodec copy -acodec copy -map 0:a:0 -map 0:v -map 0:s:m:language:eng $output_filename
  #ffmpeg -i $1 -vcodec copy -scodec copy -acodec libfdk_aac -b:a 640k -ac 6 -map 0:a -map 0:v -map 0:s:m:language:eng $output_filename
}


function yt_dlp_mp3(){
  url=$1
  yt-dlp --extract-audio --audio-format mp3 --audio-quality 0 $url
}
alias yt-dlp-mp3="yt_dlp_mp3"

function yt_dlp_m4a(){
  url=$1
  yt-dlp --extract-audio --audio-format m4a --audio-quality 0 $url
}
alias yt-dlp-m4a="yt_dlp_m4a"


alias ac3-to-aac="convert_ac3_to_aac"

function all_ac3_to_aac(){
  for file in ./*; do
    if [ -f "$file" ]; then
      ac3-to-aac $file
    fi
  done
}

alias all-ac3-to-aac="all_ac3_to_aac"

alias colima-start="colima start"

alias genplan="mkdir -p docs && touch docs/plan.excalidraw"

function create_excalidraw_file() {
  name=$1
  touch $name.excalidraw
}
alias genex="create_excalidraw_file"
