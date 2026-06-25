# --- gwt: git worktree helpers for .claude/worktrees/ ---
# Usage: gwt add <branch>       Create worktree and cd into it
#        gwt add -b <branch>    Create branch + worktree and cd into it
#        gwt cp [-f] <path>     Copy <path> from root into every worktree (-f skips the prompt)
#        gwt cd <name>          cd into an existing worktree
#        gwt zed [<name>]       Open a worktree in a new Zed window (current if no name)
#        gwt ls                 List worktrees
#        gwt rm [-f] <name>     Remove a worktree (fuzzy name like `cd`; -f/--force skips the prompt, may trail the name)
#        gwt root [-p|--path]   cd back to the main worktree root (or echo it with -p)
#        gwt status             Overview of all worktrees
#        gwt path [<name>]      Echo the absolute path of a worktree (current if no name)
#
# .worktreeinclude:
#   If $repo_root/.worktreeinclude exists, matching gitignored files are copied from
#   the main worktree into a new worktree on `gwt add`. Useful for gitignored files
#   like .env or .claude/settings.local.json that don't carry over via
#   `git worktree add`. Mirrors Claude Code's own .worktreeinclude behaviour:
#     - entries are gitignore-style patterns (globs supported; blank lines and
#       full-line # comments ignored) — git parses the file directly
#     - only untracked, gitignored files are eligible; tracked files (which arrive
#       via `git worktree add`) and non-ignored files are never copied
#   Divergences from Claude Code (which only ever copies more, never less):
#     - symlinks are dereferenced (`cp -RL`) so the worktree gets a real file —
#       Claude Code skips symlinks. Needed for symlinked gitignored files like a
#       per-checkout CLAUDE.local.md, which would otherwise be silently absent in
#       every worktree (and its mandated rules lost). Trade-off: the worktree copy
#       is a standalone snapshot and can drift from the canonical target.
#     - directory matches are copied recursively via `cp -R`; Claude Code copies
#       individual files only and skips whole directories.

__gwt_root() { git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //'; }

# The logic lives in bin/gwt-helper (Ruby, unit-tested). A subprocess cannot
# change this shell's directory, so the helper writes the cd target to the file
# named by $GWT_CD_FILE and we cd there on return — the one thing the shell must
# own. Everything else (resolution, fuzzy matching, .worktreeinclude, status)
# is the helper's job.
gwt() {
  local helper="$HOME/dotfiles/bin/gwt-helper"
  local cd_file rc
  cd_file=$(mktemp "${TMPDIR:-/tmp}/gwt-cd.XXXXXX")

  if [[ -n "$GWT_TIMING" ]]; then
    zmodload zsh/datetime
    local start=$EPOCHREALTIME
    GWT_CD_FILE="$cd_file" "$helper" "$@"
    rc=$?
    printf 'gwt[timing] total (incl. ruby boot): %.1fms\n' \
      $(( (EPOCHREALTIME - start) * 1000 )) >&2
  else
    GWT_CD_FILE="$cd_file" "$helper" "$@"
    rc=$?
  fi

  if [[ -s "$cd_file" ]]; then cd "$(<"$cd_file")"; fi
  rm -f "$cd_file"
  return $rc
}

# Tab completion
_gwt() {
  local root=$(__gwt_root)
  if [[ -z "$root" ]]; then return; fi
  local wt_base="$root/${GWT_WORKTREE_DIR:-.claude/worktrees}"

  if (( CURRENT == 2 )); then
    compadd -- add cp cd zed ls rm root status path
  elif (( CURRENT == 3 )); then
    case "${words[2]}" in
      cd|rm|path|zed)
        if [[ -d "$wt_base" ]]; then
          compadd -- "$wt_base"/*(/:t)
        fi
        ;;
      cp)
        _files -W "$root"
        ;;
      add)
        # Complete branch names
        compadd -- $(git branch --format='%(refname:short)' 2>/dev/null)
        ;;
      root)
        compadd -- -p --path
        ;;
    esac
  fi
}
compdef _gwt gwt
