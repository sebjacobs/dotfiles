# --- proj: quick cd into personal, client, or open-source projects ---
# Usage:
#   proj <name>              cd into a personal project (e.g. `proj cadence`)
#   proj <client>/<name>     cd into a namespaced client project
#                            (e.g. `proj nesta/asf_visit_a_heat_pump`)
#   proj .                   cd to the current project root
#   proj                     print current project, or list all available
#
# The searchable project trees are declared in bin/proj-helper's TREES list;
# add a new kind of project (a new root dir) there in one line.

PROJ_CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/proj/keys"

# The logic lives in bin/proj-helper (Ruby, unit-tested). A subprocess cannot
# change this shell's directory, so the helper writes the cd target to the file
# named by $PROJ_CD_FILE and we cd there on return — the one thing the shell
# must own. The helper also rewrites $PROJ_CACHE_FILE (the project name list) on
# every run, so completion stays Ruby-free.
proj() {
  local helper="$HOME/dotfiles/bin/proj-helper"
  local cd_file rc
  cd_file=$(mktemp "${TMPDIR:-/tmp}/proj-cd.XXXXXX")

  PROJ_CD_FILE="$cd_file" PROJ_CACHE_FILE="$PROJ_CACHE_FILE" "$helper" "$@"
  rc=$?

  if [[ -s "$cd_file" ]]; then cd "$(<"$cd_file")"; fi
  rm -f "$cd_file"
  return $rc
}

# Tab completion reads the cached name list rather than spawning Ruby per
# keypress. A cold cache is warmed once with a single `--list` call.
_proj() {
  if [[ ! -s "$PROJ_CACHE_FILE" ]]; then
    PROJ_CACHE_FILE="$PROJ_CACHE_FILE" "$HOME/dotfiles/bin/proj-helper" --list >/dev/null 2>&1
  fi
  [[ -s "$PROJ_CACHE_FILE" ]] && compadd -- "${(@f)$(<$PROJ_CACHE_FILE)}"
}
compdef _proj proj
