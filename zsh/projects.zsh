# --- proj: quick cd into personal, client, or open-source projects ---
# Usage:
#   proj <name>              cd into a personal project (e.g. `proj cadence`)
#   proj <name> <worktree>   cd into a worktree under the project, with
#                            tab-completion on the worktree name (delegates to gwt)
#   proj <client>/<name>     cd into a namespaced client project
#                            (e.g. `proj nesta/asf_visit_a_heat_pump`)
#   proj .                   cd to the current project root
#   proj                     print current project, or list all available
#
# The searchable project trees are declared in lib/proj.rb's TREES list;
# add a new kind of project (a new root dir) there in one line.

PROJ_CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/proj/keys"
PROJ_PATHS_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/proj/paths"

# The logic lives in lib/proj.rb (Ruby, unit-tested). A subprocess cannot
# change this shell's directory, so the helper writes the cd target to the file
# named by $PROJ_CD_FILE and we cd there on return — the one thing the shell
# must own. The helper also rewrites $PROJ_CACHE_FILE (the project name list) on
# every run, so completion stays Ruby-free.
proj() {
  local helper="$HOME/dotfiles/lib/proj.rb"
  local cd_file rc
  cd_file=$(mktemp "${TMPDIR:-/tmp}/proj-cd.XXXXXX")

  PROJ_CD_FILE="$cd_file" PROJ_CACHE_FILE="$PROJ_CACHE_FILE" PROJ_PATHS_FILE="$PROJ_PATHS_FILE" "$helper" "$@"
  rc=$?

  if [[ -s "$cd_file" ]]; then cd "$(<"$cd_file")"; fi
  rm -f "$cd_file"
  return $rc
}

# Echo the project path cached for an exact display-name, or nothing. The helper
# writes the name->path map to $PROJ_PATHS_FILE on every run, so this stays Ruby-free.
_proj_path_for() {
  local key="$1" k v
  [[ -s "$PROJ_PATHS_FILE" ]] || return
  while IFS=$'\t' read -r k v; do
    [[ "$k" == "$key" ]] && { print -r -- "$v"; return; }
  done < "$PROJ_PATHS_FILE"
}

# Cached keys matching a query the way lib/proj.rb's fuzzy_match does: prefix
# matches win over substring matches, and a `/` in the query matches each
# segment of a namespaced key independently (so `nest/heat` resolves
# `nesta/asf_visit_a_heat_pump`). Echoes the matching keys, one per line, so
# completion mirrors what `proj` itself would resolve — without booting Ruby.
_proj_match_keys() {
  local query="$1" k qc qp kc kp
  [[ -s "$PROJ_CACHE_FILE" ]] || return
  local -a keys prefix substr
  keys=("${(@f)$(<$PROJ_CACHE_FILE)}")
  if [[ "$query" == */* ]]; then
    qc="${query%%/*}"; qp="${query#*/}"
    for k in $keys; do
      [[ "$k" == */* ]] || continue
      kc="${k%%/*}"; kp="${k#*/}"
      if [[ "$kc" == "$qc"* && "$kp" == "$qp"* ]]; then
        prefix+=("$k")
      elif [[ "$kc" == *"$qc"* && "$kp" == *"$qp"* ]]; then
        substr+=("$k")
      fi
    done
  else
    for k in $keys; do
      if [[ "$k" == "$query"* ]]; then
        prefix+=("$k")
      elif [[ "$k" == *"$query"* ]]; then
        substr+=("$k")
      fi
    done
  fi
  if (( ${#prefix} )); then print -rl -- $prefix; elif (( ${#substr} )); then print -rl -- $substr; fi
}

# Tab completion reads the cached name list rather than spawning Ruby per
# keypress. A cold cache is warmed once with a single `--list` call. The first
# argument fuzzy-matches project names (so `asf` completes
# `nesta/asf_visit_a_heat_pump`); the second completes worktree names under the
# chosen project, resolving a partial project name the same way.
_proj() {
  if [[ ! -s "$PROJ_CACHE_FILE" || ! -s "$PROJ_PATHS_FILE" ]]; then
    PROJ_CACHE_FILE="$PROJ_CACHE_FILE" PROJ_PATHS_FILE="$PROJ_PATHS_FILE" \
      "$HOME/dotfiles/lib/proj.rb" --list >/dev/null 2>&1
  fi

  if (( CURRENT == 2 )); then
    local -a matches
    matches=("${(@f)$(_proj_match_keys "${words[2]}")}")
    (( ${#matches} )) && compadd -U -- $matches
  elif (( CURRENT == 3 )); then
    local -a matches
    matches=("${(@f)$(_proj_match_keys "${words[2]}")}")
    local key="${words[2]}"
    (( ${#matches} == 1 )) && key="$matches[1]"
    local path=$(_proj_path_for "$key")
    [[ -n "$path" ]] || return
    local wt_base="$path/${GWT_WORKTREE_DIR:-.claude/worktrees}"
    [[ -d "$wt_base" ]] && compadd -- "$wt_base"/*(/:t)
  fi
}
compdef _proj proj
