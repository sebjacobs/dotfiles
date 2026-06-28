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
# every run, so completion stays Ruby-free.
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

# Echo the project path cached for an exact display-name, or nothing. The helper
# writes the name->path map to $PROJ_PATHS_FILE on every run, so this stays Ruby-free.
_proj_path_for() {
  local key="$1" k v
  [[ -s "$PROJ_PATHS_FILE" ]] || return
  while IFS=$'\t' read -r k v || [[ -n "$k" ]]; do
    [[ "$k" == "$key" ]] && { print -r -- "$v"; return; }
  done < "$PROJ_PATHS_FILE"
}

# Cached keys matching a query the way lib/proj.rb's fuzzy_match does: prefix
# matches win over substring matches, and a `/` in the query matches each
# segment of a namespaced key independently (so `acm/wid` resolves
# `acme/widget-tracker`). Echoes the matching keys, one per line, so
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
# argument fuzzy-matches project names (so `wid` completes
# `acme/widget-tracker`), grouped by type in the manifest's order (derived from
# the cached name->type map, not hardcoded) so a new type needs no edit here;
# the second completes worktree names under the chosen project, resolving a
# partial project name the same way.
_proj() {
  if [[ ! -s "$PROJ_CACHE_FILE" || ! -s "$PROJ_PATHS_FILE" || ! -s "$PROJ_TYPES_FILE" || ! -s "$PROJ_TAGS_FILE" ]]; then
    PROJ_CACHE_FILE="$PROJ_CACHE_FILE" PROJ_PATHS_FILE="$PROJ_PATHS_FILE" PROJ_TYPES_FILE="$PROJ_TYPES_FILE" PROJ_TAGS_FILE="$PROJ_TAGS_FILE" \
      "$HOME/dotfiles/lib/proj.rb" --list >/dev/null 2>&1
  fi

  # `proj ls ...`: after --tag complete the cached tag vocabulary; otherwise
  # complete the type names (the positional) plus the --tag flag itself.
  if (( CURRENT >= 3 )) && [[ "${words[2]}" == ls ]]; then
    if [[ "${words[CURRENT-1]}" == --tag ]]; then
      [[ -s "$PROJ_TAGS_FILE" ]] && compadd -- "${(@f)$(<$PROJ_TAGS_FILE)}"
    else
      local -a tnames
      [[ -s "$PROJ_TYPES_FILE" ]] && tnames=("${(@f)$(cut -f2 "$PROJ_TYPES_FILE" | sort -u)}")
      compadd -- $tnames --tag
    fi
    return
  fi

  # `proj mv <project> <new-name>`: complete the project to rename in slot one;
  # the new name is free text, so slot two offers nothing.
  if (( CURRENT == 3 )) && [[ "${words[2]}" == mv ]]; then
    local -a matches
    matches=("${(@f)$(_proj_match_keys "${words[3]}")}")
    (( ${#matches} )) && compadd -- $matches
    return
  fi

  if (( CURRENT == 2 )); then
    # The cached types file lists keys in tree order, so its distinct types in
    # first-seen order are the manifest's group order — no hardcoded type list.
    local -a type_order
    [[ -s "$PROJ_TYPES_FILE" ]] && type_order=("${(@f)$(awk -F'\t' '!seen[$2]++ { print $2 }' "$PROJ_TYPES_FILE")}")

    zstyle ':completion:*:*:proj:*' group-name ''
    zstyle ':completion:*:*:proj:*' group-order commands $type_order
    local -a _subcommands=(ls status mv)  # @subcommands
    compadd -J commands -X 'commands' -- $_subcommands

    local -a matches
    matches=("${(@f)$(_proj_match_keys "${words[2]}")}")
    (( ${#matches} )) || return

    typeset -A typeof
    if [[ -s "$PROJ_TYPES_FILE" ]]; then
      local k v
      while IFS=$'\t' read -r k v || [[ -n "$k" ]]; do typeof[$k]=$v; done < "$PROJ_TYPES_FILE"
    fi

    local t m
    for t in $type_order; do
      local -a group
      group=()
      for m in $matches; do [[ "${typeof[$m]}" == "$t" ]] && group+=$m; done
      (( ${#group} )) && compadd -U -J "$t" -X "$t" -- $group
    done

    local -a untyped
    for m in $matches; do [[ -z "${typeof[$m]}" ]] && untyped+=$m; done
    (( ${#untyped} )) && compadd -U -- $untyped
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
