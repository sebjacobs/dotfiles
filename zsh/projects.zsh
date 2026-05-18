# --- proj: quick cd into personal or client projects ---
# Usage:
#   proj <name>              cd into a personal project (e.g. `proj cadence`)
#   proj <client>/<name>     cd into a namespaced client project
#                            (e.g. `proj nesta/asf_visit_a_heat_pump`)
#   proj .                   cd to the current project root
#   proj                     print current project, or list all available

PROJ_DIR="$HOME/Tech/Projects/personal"
CLIENT_DIR="$HOME/Tech/Projects/client"

proj() {
  local name="$1"

  # Resolve the current project root if cwd is inside a known projects tree.
  local _proj_root=""
  if [[ "$PWD/" == "$PROJ_DIR"/*/* ]]; then
    local rel="${PWD#$PROJ_DIR/}"
    local first="${rel%%/*}"
    if [[ "$first" == "PRIVATE" ]]; then
      local rest="${rel#PRIVATE/}"
      _proj_root="$PROJ_DIR/PRIVATE/${rest%%/*}"
    elif [[ "$first" != "ARCHIVE" ]]; then
      _proj_root="$PROJ_DIR/$first"
    fi
  elif [[ "$PWD/" == "$CLIENT_DIR"/*/*/* ]]; then
    local rel="${PWD#$CLIENT_DIR/}"
    local client_name="${rel%%/*}"
    local rest="${rel#$client_name/}"
    local proj_name="${rest%%/*}"
    if [[ "$client_name" != "ARCHIVE" && "$proj_name" != "ARCHIVE" ]]; then
      _proj_root="$CLIENT_DIR/$client_name/$proj_name"
    fi
  fi

  # `proj .` — cd to current project root.
  if [[ "$name" == "." ]]; then
    if [[ -z "$_proj_root" ]]; then
      echo "proj: not inside a project under $PROJ_DIR or $CLIENT_DIR" >&2
      return 1
    fi
    cd "$_proj_root"
    return 0
  fi

  # Build display-name -> path map across all known trees.
  # PRIVATE iterated first so personal/* overwrites on basename collision
  # (e.g. session-logs exists in both — personal wins for `proj session-logs`).
  local -A projects
  local d base cname pname
  for d in "$PROJ_DIR"/PRIVATE/*(N/); do
    base="${d:t}"
    [[ "$base" == "ARCHIVE" ]] && continue
    projects[$base]="$d"
  done
  for d in "$PROJ_DIR"/*(N/); do
    base="${d:t}"
    [[ "$base" == "ARCHIVE" || "$base" == "PRIVATE" ]] && continue
    projects[$base]="$d"
  done
  for d in "$CLIENT_DIR"/*/*(N/); do
    cname="${d:h:t}"
    pname="${d:t}"
    [[ "$cname" == "ARCHIVE" || "$pname" == "ARCHIVE" ]] && continue
    projects[$cname/$pname]="$d"
  done

  if [[ -z "$name" ]]; then
    # Bare `proj` inside a project prints its path.
    if [[ -n "$_proj_root" ]]; then
      echo "$_proj_root"
      return 0
    fi
    echo "Usage: proj <name>"
    echo ""
    print -l ${(k)projects} | sort
    return 1
  fi

  # Exact match against display names (handles `nesta/foo` too).
  if [[ -n "${projects[$name]}" ]]; then
    cd "${projects[$name]}"
    return 0
  fi

  # Fuzzy: prefix then substring across display names.
  # If the query contains `/`, match each segment independently against
  # namespaced client keys — `proj nest/heat` resolves nesta/asf_visit_a_heat_pump.
  local -a keys=(${(k)projects})
  local -a matches
  if [[ "$name" == */* ]]; then
    local qc="${name%%/*}" qp="${name#*/}"
    local k kc kp
    for k in ${(M)keys:#*/*}; do
      kc="${k%%/*}"; kp="${k#*/}"
      [[ "$kc" == "$qc"* && "$kp" == "$qp"* ]] && matches+=("$k")
    done
    if (( ${#matches} == 0 )); then
      for k in ${(M)keys:#*/*}; do
        kc="${k%%/*}"; kp="${k#*/}"
        [[ "$kc" == *"$qc"* && "$kp" == *"$qp"* ]] && matches+=("$k")
      done
    fi
  else
    matches=(${(M)keys:#${name}*})
    if (( ${#matches} == 0 )); then
      matches=(${(M)keys:#*${name}*})
    fi
  fi

  case ${#matches} in
    0) echo "No project matching: $name" >&2; return 1 ;;
    1) cd "${projects[$matches[1]]}" ;;
    *)
      echo "Multiple projects match '$name':" >&2
      for m in $matches; do echo "  $m" >&2; done
      return 1
      ;;
  esac
}

_proj() {
  local d base cname pname
  local -a dirs
  for d in "$PROJ_DIR"/*(N/); do
    base="${d:t}"
    [[ "$base" == "ARCHIVE" || "$base" == "PRIVATE" ]] && continue
    dirs+=("$base")
  done
  for d in "$PROJ_DIR"/PRIVATE/*(N/); do
    base="${d:t}"
    [[ "$base" == "ARCHIVE" ]] && continue
    dirs+=("$base")
  done
  for d in "$CLIENT_DIR"/*/*(N/); do
    cname="${d:h:t}"
    pname="${d:t}"
    [[ "$cname" == "ARCHIVE" || "$pname" == "ARCHIVE" ]] && continue
    dirs+=("$cname/$pname")
  done
  compadd -- ${(u)dirs}
}
compdef _proj proj
