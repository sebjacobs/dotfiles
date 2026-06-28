# --- proj: quick cd into personal, client, or open-source projects ---
# Usage:
#   proj <name>              cd into a personal project (e.g. `proj cadence`)
#   proj <name> <worktree>   cd into a worktree under the project, with
#                            tab-completion on the worktree name (delegates to gwt)
#   proj <client>/<name>     cd into a namespaced client project
#                            (e.g. `proj acme/widget-tracker`)
#   proj ls [<type>] [--tag T...]
#                            list projects grouped by type (the categories
#                            declared in $PROJ_ROOT/.projroot, e.g. personal,
#                            private, client, opensource), optionally narrowed to
#                            a type and/or tags (repeatable --tag; carry all).
#                            Tags come from each project's gitignored .proj file
#                            and show inline in the listing.
#   proj status              list git projects newest-first by their most-recent
#                            commit, each row showing the project name, the branch
#                            (across main + worktrees) carrying that commit, and
#                            the timestamp (the `(last: …)` shape jotter ls uses).
#                            The per-project equivalent is `gwt status`.
#   proj mv <project> <new-name>
#                            rename a project's directory and carry its
#                            per-checkout history: Claude transcripts (project +
#                            worktrees) and jotter logs (via `jotter mv`).
#                            Confirms first. <new-name> is a single path segment.
#   proj .                   cd to the current project root
#   proj                     inside a project print its root, else list all (`ls`)
#
# The searchable project trees are declared in the $PROJ_ROOT/.projroot
# manifest; add a new kind of project (a new root dir) there in one line.

PROJ_CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/proj/keys"
PROJ_PATHS_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/proj/paths"
PROJ_TYPES_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/proj/types"
PROJ_TAGS_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/proj/tags"

# The logic lives in lib/proj.rb (Ruby, unit-tested). A subprocess cannot
# change this shell's directory, so the helper writes the cd target to the file
# named by $PROJ_CD_FILE and we cd there on return — the one thing the shell
# must own. The helper also rewrites $PROJ_CACHE_FILE (the project name list) on
# every run, so completion stays Ruby-free. Tab completion (reading those caches)
# lives in the autoloaded zsh/completions/_proj, alongside the other CLIs'.
proj() {
  local helper="$HOME/dotfiles/lib/proj.rb"
  local cd_file rc
  cd_file=$(mktemp "${TMPDIR:-/tmp}/proj-cd.XXXXXX")

  PROJ_CD_FILE="$cd_file" PROJ_CACHE_FILE="$PROJ_CACHE_FILE" PROJ_PATHS_FILE="$PROJ_PATHS_FILE" PROJ_TYPES_FILE="$PROJ_TYPES_FILE" PROJ_TAGS_FILE="$PROJ_TAGS_FILE" "$helper" "$@"
  rc=$?

  if [[ -s "$cd_file" ]]; then cd "$(<"$cd_file")"; fi
  rm -f "$cd_file"
  return $rc
}
