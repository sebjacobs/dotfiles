# --- gwt: git worktree helpers for .claude/worktrees/ ---
# Usage: gwt add <branch>       Create worktree and cd into it
#        gwt add -b <branch>    Create branch + worktree and cd into it
#        gwt cd <name>          cd into an existing worktree
#        gwt ls                 List worktrees
#        gwt rm <name>          Remove a worktree
#        gwt root               cd back to the main worktree root

__gwt_root() { git rev-parse --show-toplevel 2>/dev/null; }

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
      local wt_dir="$wt_base/$name"
      if [[ ! -d "$wt_dir" ]]; then echo "No worktree: $name" >&2; return 1; fi
      cd "$wt_dir"
      ;;

    ls)
      if [[ ! -d "$wt_base" ]] || [[ -z "$(ls -A "$wt_base" 2>/dev/null)" ]]; then
        echo "No worktrees in .claude/worktrees/"
        return 0
      fi
      for dir in "$wt_base"/*/; do
        local name=$(basename "$dir")
        local branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "???")
        printf "  %-40s %s\n" "$name" "$branch"
      done
      ;;

    root)
      local main_root=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
      cd "$main_root"
      ;;

    rm)
      local name="$1"
      if [[ -z "$name" ]]; then echo "Usage: gwt rm <name>" >&2; return 1; fi
      local wt_dir="$wt_base/$name"
      if [[ ! -d "$wt_dir" ]]; then echo "No worktree: $name" >&2; return 1; fi
      git worktree remove "$wt_dir"
      ;;

    *)
      echo "Usage: gwt <add|cd|ls|rm|root> [args]"
      echo ""
      echo "  add [-b] <branch>    Create worktree and cd into it"
      echo "  cd <name>           cd into an existing worktree"
      echo "  ls                  List worktrees"
      echo "  rm <name>           Remove a worktree"
      echo "  root                cd back to the main worktree root"
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
    compadd -- add cd ls rm root
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
