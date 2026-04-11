# --- gwt: git worktree helpers for .claude/worktrees/ ---
# Usage: gwt add <branch>       Create worktree and cd into it
#        gwt add -b <branch>    Create branch + worktree and cd into it
#        gwt cd <name>          cd into an existing worktree
#        gwt ls                 List worktrees
#        gwt rm <name>          Remove a worktree (with confirmation)
#        gwt root               cd back to the main worktree root
#        gwt status             Overview of all worktrees

__gwt_root() { git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //'; }

__gwt_short() {
  local name="$1"
  name="${name#feature/}"
  name="${name#bugfix/}"
  name="${name#hotfix/}"
  echo "$name"
}

gwt() {
  local root=$(__gwt_root)
  if [[ -z "$root" ]]; then echo "Not in a git repo" >&2; return 1; fi
  local wt_base="$root/.claude/worktrees"

  local cmd="$1"; shift 2>/dev/null

  case "$cmd" in
    add)
      local create_branch=false
      if [[ "$1" == "-b" ]]; then create_branch=true; shift; fi
      local branch="$1"
      if [[ -z "$branch" ]]; then echo "Usage: gwt add [-b] <branch>" >&2; return 1; fi

      local short=$(__gwt_short "$branch")
      local wt_dir="$wt_base/$short"

      if [[ -d "$wt_dir" ]]; then
        echo "Worktree already exists, cd-ing into it"
        cd "$wt_dir"
        return 0
      fi

      if $create_branch; then
        git worktree add -b "$branch" "$wt_dir"
      else
        git worktree add "$wt_dir" "$branch"
      fi
      if [[ $? -eq 0 ]]; then cd "$wt_dir"; fi
      ;;

    cd)
      local name="$1"
      if [[ -z "$name" ]]; then echo "Usage: gwt cd <name>" >&2; return 1; fi

      # Exact match
      if [[ -d "$wt_base/$name" ]]; then
        cd "$wt_base/$name"
        return 0
      fi

      # Fuzzy: prefix then substring
      if [[ ! -d "$wt_base" ]]; then echo "No worktree matching: $name" >&2; return 1; fi
      local -a matches
      matches=("$wt_base"/${name}*(N/:t))
      if (( ${#matches} == 0 )); then
        matches=("$wt_base"/*${name}*(N/:t))
      fi

      case ${#matches} in
        0) echo "No worktree matching: $name" >&2; return 1 ;;
        1) cd "$wt_base/$matches[1]" ;;
        *)
          echo "Multiple worktrees match '$name':" >&2
          for m in $matches; do echo "  $m" >&2; done
          return 1
          ;;
      esac
      ;;

    ls)
      if [[ ! -d "$wt_base" ]] || [[ -z "$(ls -A "$wt_base" 2>/dev/null)" ]]; then
        echo "No worktrees in .claude/worktrees/"
        return 0
      fi
      for dir in "$wt_base"/*/; do
        local name=$(basename "$dir")
        local branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "???")
        local marker="  "
        if [[ "$PWD" == "${dir%/}"* ]]; then marker="* "; fi
        printf "%s%-40s %s\n" "$marker" "$name" "$branch"
      done
      ;;

    root)
      local main_root=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
      cd "$main_root"
      ;;

    status)
      if [[ ! -d "$wt_base" ]] || [[ -z "$(ls -A "$wt_base" 2>/dev/null)" ]]; then
        echo "No worktrees in .claude/worktrees/"
        return 0
      fi
      local main_branch=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
      for dir in "$wt_base"/*/; do
        local name=$(basename "$dir")
        local branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "???")
        local dirty=""
        if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then dirty=" [dirty]"; fi
        local ahead behind counts
        counts=$(git -C "$dir" rev-list --left-right --count "$main_branch"..."$branch" 2>/dev/null)
        behind=${counts%%$'\t'*}
        ahead=${counts##*$'\t'}
        local position=""
        if [[ "${ahead:-0}" -gt 0 && "${behind:-0}" -gt 0 ]]; then
          position=" ↑${ahead} ↓${behind}"
        elif [[ "${ahead:-0}" -gt 0 ]]; then
          position=" ↑${ahead}"
        elif [[ "${behind:-0}" -gt 0 ]]; then
          position=" ↓${behind}"
        fi
        local marker="  "
        if [[ "$PWD" == "${dir%/}"* ]]; then marker="* "; fi
        printf "%s%-30s %-30s%s%s\n" "$marker" "$name" "$branch" "$dirty" "$position"
      done
      ;;

    rm)
      local name="$1"
      if [[ -z "$name" ]]; then echo "Usage: gwt rm <name>" >&2; return 1; fi
      local wt_dir="$wt_base/$name"
      if [[ ! -d "$wt_dir" ]]; then echo "No worktree: $name" >&2; return 1; fi

      echo "Remove worktree '$name'? [y/N] "
      read -q || { echo; return 1; }
      echo

      # cd out if we're inside the worktree being removed
      if [[ "$PWD" == "$wt_dir"* ]]; then cd "$root"; fi

      git worktree remove "$wt_dir"
      ;;

    *)
      echo "Usage: gwt <add|cd|ls|rm|root|status> [args]"
      echo ""
      echo "  add [-b] <branch>    Create worktree and cd into it"
      echo "  cd <name>           cd into an existing worktree"
      echo "  ls                  List worktrees"
      echo "  rm <name>           Remove a worktree"
      echo "  root                cd back to the main worktree root"
      echo "  status              Overview of all worktrees"
      return 1
      ;;
  esac
}

# Tab completion
_gwt() {
  local root=$(__gwt_root)
  if [[ -z "$root" ]]; then return; fi
  local wt_base="$root/.claude/worktrees"

  if (( CURRENT == 2 )); then
    compadd -- add cd ls rm root status
  elif (( CURRENT == 3 )); then
    case "${words[2]}" in
      cd|rm)
        if [[ -d "$wt_base" ]]; then
          compadd -- "$wt_base"/*(/:t)
        fi
        ;;
      add)
        # Complete branch names
        compadd -- $(git branch --format='%(refname:short)' 2>/dev/null)
        ;;
    esac
  fi
}
compdef _gwt gwt
