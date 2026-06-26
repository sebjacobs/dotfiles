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
# The searchable project trees are declared in bin/proj-helper's TREES list;
# add a new kind of project (a new root dir) there in one line.

PROJ_CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/proj/keys"
PROJ_PATHS_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/proj/paths"

# The logic lives in bin/proj-helper (Ruby, unit-tested). A subprocess cannot
# change this shell's directory, so the helper writes the cd target to the file
# named by $PROJ_CD_FILE and we cd there on return — the one thing the shell
# must own. The helper also rewrites $PROJ_CACHE_FILE (the project name list) on
# every run, so completion stays Ruby-free.
proj() {
  local helper="$HOME/dotfiles/bin/proj-helper"
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

# Tab completion reads the cached name list rather than spawning Ruby per
# keypress. A cold cache is warmed once with a single `--list` call. The second
# argument completes worktree names under the chosen project's worktree dir.
_proj() {
  if [[ ! -s "$PROJ_CACHE_FILE" || ! -s "$PROJ_PATHS_FILE" ]]; then
    PROJ_CACHE_FILE="$PROJ_CACHE_FILE" PROJ_PATHS_FILE="$PROJ_PATHS_FILE" \
      "$HOME/dotfiles/bin/proj-helper" --list >/dev/null 2>&1
  fi

  if (( CURRENT == 2 )); then
    [[ -s "$PROJ_CACHE_FILE" ]] && compadd -- "${(@f)$(<$PROJ_CACHE_FILE)}"
  elif (( CURRENT == 3 )); then
    local path=$(_proj_path_for "${words[2]}")
    [[ -n "$path" ]] || return
    local wt_base="$path/${GWT_WORKTREE_DIR:-.claude/worktrees}"
    [[ -d "$wt_base" ]] && compadd -- "$wt_base"/*(/:t)
  fi
}
compdef _proj proj
