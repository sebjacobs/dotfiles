# --- proj: quick cd into personal, client, or open-source projects ---
# Usage:
#   proj <name>              cd into a personal project (e.g. `proj cadence`)
#   proj <name> <worktree>   cd into a worktree under the project, with
#                            tab-completion on the worktree name (delegates to gwt)
#   proj <client>/<name>     cd into a namespaced client project
#                            (e.g. `proj acme/widget-tracker`)
#   proj cd <category>       cd into a category's root directory (the tree its
#                            projects sit under), named by the category as it
#                            appears in `proj ls` — e.g. `proj cd personal`,
#                            `proj cd private`, `proj cd client`.
#   proj ls [<type>] [--tag T...]
#                            list projects grouped by type (the categories
#                            declared in $PROJ_ROOT/.projroot, e.g. personal,
#                            private, client, opensource), optionally narrowed to
#                            a type and/or tags (repeatable --tag; carry all).
#                            Tags and a one-line description come from each
#                            project's gitignored .proj file and show inline;
#                            projects flagged `starred: true` there show yellow
#                            (in `ls` and in `proj <Tab>`).
#   proj show <name>         show a project's path, description, tags, and its
#                            most-recent branch + commit time (like `proj status`
#                            for one project).
#   proj init                scaffold a commented-out .proj (description + tags)
#                            at the current project root; won't clobber an
#                            existing one. Uncomment the fields you want.
#   proj status              list git projects newest-first by their most-recent
#                            commit, each row showing the project name, the branch
#                            (across main + worktrees) carrying that commit, and
#                            the timestamp (the `(last: …)` shape jotter ls uses).
#                            The per-project equivalent is `gwt status`.
#   proj branches            list the current project's local branches newest-first
#                            by their most-recent commit, marking the checked-out
#                            branch with `* ` and stamping each with its last-commit
#                            time — `gwt status` for branches rather than worktrees.
#   proj mv <project> <new-name>
#                            rename a project's directory and carry its
#                            per-checkout history: Claude transcripts (project +
#                            worktrees) and jotter logs (via `jotter mv`).
#                            Confirms first. <new-name> is a single path segment.
#   proj mv --category <old> <new>
#                            rename a whole category (a .projroot tree): rename
#                            its directory, migrate every project's Claude
#                            history to the new path prefix, and rewrite the
#                            manifest line (commit that in dotfiles yourself).
#                            <old> is the category as `proj ls` shows it; <new>
#                            is the new dir basename. Confirms first.
#   proj archive <project>   move a project into its category's ARCHIVE folder
#                            (kept out of every listing), carrying the same
#                            per-checkout history mv does. Confirms first.
#   proj .                   cd to the current project root
#   proj -                   cd to the previous directory (toggles, like `cd -`);
#                            `proj cd -` is the same. First run / a vanished dir
#                            errors rather than moving.
#   proj                     inside a project print its root, else list all (`ls`)
#
# The searchable project trees are declared in the $PROJ_ROOT/.projroot
# manifest; add a new kind of project (a new root dir) there in one line.

PROJ_CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/proj/keys"
PROJ_PATHS_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/proj/paths"
PROJ_TYPES_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/proj/types"
PROJ_TAGS_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/proj/tags"
PROJ_STARRED_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/proj/starred"
# The one file proj-bin both reads and writes: the directory it last left, so
# `proj -` (and `proj cd -`) toggles back to it across separate invocations.
PROJ_PREV_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/proj/prev"

# Paint starred (favourite) projects yellow in `proj <Tab>`. Completion colours
# individual matches via the `list-colors` style, but that style is only honoured
# under the broad `default`-tag context (it can't be scoped to the proj command),
# and it must be set *outside* a completion call — setting it from inside the
# _proj function is too late to take effect. So the colours are applied here at
# shell init and refreshed by the proj() wrapper below whenever the starred cache
# is rewritten, giving a live update the next time you Tab. One anchored
# `=name=01;33` (bold yellow) entry per starred key colours exactly those matches;
# (b) backslash-quotes any glob metacharacter in a name. LS_COLORS' file rules
# ride along so file-name completion keeps its usual colours.
_proj_apply_star_colors() {
  [[ -s "$PROJ_STARRED_FILE" ]] || return
  local -a star_colors
  local s
  for s in ${(f)"$(<$PROJ_STARRED_FILE)"}; do star_colors+=("=${(b)s}=01;33"); done
  zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS} $star_colors
}
_proj_apply_star_colors

# The logic is the proj-bin binary (a Go port of the old lib/proj.rb, in the
# proj repo). A subprocess cannot change this shell's directory, so proj-bin
# writes the cd target to the file named by $PROJ_CD_FILE and we cd there on
# return — the one thing the shell must own. proj-bin also rewrites
# $PROJ_CACHE_FILE (the project name list) on every run, so completion stays
# boot-free. Tab completion (reading those caches) lives in the autoloaded
# zsh/completions/_proj, alongside the other CLIs'.
proj() {
  local helper="$HOME/.local/bin/proj-bin"
  local cd_file rc
  cd_file=$(mktemp "${TMPDIR:-/tmp}/proj-cd.XXXXXX")

  PROJ_CD_FILE="$cd_file" PROJ_CACHE_FILE="$PROJ_CACHE_FILE" PROJ_PATHS_FILE="$PROJ_PATHS_FILE" PROJ_TYPES_FILE="$PROJ_TYPES_FILE" PROJ_TAGS_FILE="$PROJ_TAGS_FILE" PROJ_STARRED_FILE="$PROJ_STARRED_FILE" PROJ_PREV_FILE="$PROJ_PREV_FILE" "$helper" "$@"
  rc=$?

  if [[ -s "$cd_file" ]]; then cd "$(<"$cd_file")"; fi
  rm -f "$cd_file"
  # The helper rewrote the starred cache; refresh the completion colours so a
  # just-edited `.proj` shows yellow on the next Tab without a new shell.
  _proj_apply_star_colors
  return $rc
}
