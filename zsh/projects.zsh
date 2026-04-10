# --- proj: quick cd into personal projects ---
# Usage: proj <name>    cd into ~/Tech/Projects/personal/<name>

PROJ_DIR="$HOME/Tech/Projects/personal"

proj() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Usage: proj <name>"
    echo ""
    print -l "$PROJ_DIR"/*(/:t) "$PROJ_DIR"/private/*(/:t) | grep -Ev '^(ARCHIVE|private)$' | sort
    return 1
  fi
  if [[ -d "$PROJ_DIR/$name" ]]; then
    cd "$PROJ_DIR/$name"
  elif [[ -d "$PROJ_DIR/private/$name" ]]; then
    cd "$PROJ_DIR/private/$name"
  else
    echo "No project: $name" >&2; return 1
  fi
}

_proj() {
  local -a dirs
  dirs=("$PROJ_DIR"/*(/:t) "$PROJ_DIR"/private/*(/:t))
  dirs=(${dirs:#(ARCHIVE|private)})
  compadd -- $dirs
}
compdef _proj proj
