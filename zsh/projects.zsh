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
  # Exact match
  if [[ -d "$PROJ_DIR/$name" ]]; then
    cd "$PROJ_DIR/$name"
    return 0
  elif [[ -d "$PROJ_DIR/private/$name" ]]; then
    cd "$PROJ_DIR/private/$name"
    return 0
  fi

  # Lazy match: prefix then substring (across both dirs)
  local -a matches
  matches=("$PROJ_DIR"/${name}*(N/:t) "$PROJ_DIR"/private/${name}*(N/:t))
  matches=(${matches:#(ARCHIVE|private)})
  if (( ${#matches} == 0 )); then
    matches=("$PROJ_DIR"/*${name}*(N/:t) "$PROJ_DIR"/private/*${name}*(N/:t))
    matches=(${matches:#(ARCHIVE|private)})
  fi

  case ${#matches} in
    0) echo "No project matching: $name" >&2; return 1 ;;
    1)
      if [[ -d "$PROJ_DIR/$matches[1]" ]]; then
        cd "$PROJ_DIR/$matches[1]"
      else
        cd "$PROJ_DIR/private/$matches[1]"
      fi
      ;;
    *)
      echo "Multiple projects match '$name':" >&2
      for m in $matches; do echo "  $m" >&2; done
      return 1
      ;;
  esac
}

_proj() {
  local -a dirs
  dirs=("$PROJ_DIR"/*(/:t) "$PROJ_DIR"/private/*(/:t))
  dirs=(${dirs:#(ARCHIVE|private)})
  compadd -- $dirs
}
compdef _proj proj
