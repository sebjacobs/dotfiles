# --- gwt: git worktree helpers for .claude/worktrees/ ---
# Usage: gwt add <branch>       Create worktree and cd into it
#        gwt add -b <branch>    Create branch + worktree and cd into it
#        gwt add -b <new>:<from>  Branch <new> off <from>'s tip (works even if <from>
#                                 is already checked out elsewhere) + worktree
#        gwt cp [-f] <path>     Copy <path> from root into every worktree (-f skips the prompt)
#        gwt cd <name>          cd into an existing worktree
#        gwt mv [-f] <name> <new-name>  Rename a worktree's dir + its Claude history (branch unchanged; -f skips the prompt)
#        gwt <name>             Shorthand for `gwt cd <name>` (any non-subcommand name)
#        gwt zed [<name>]       Open a worktree in a new Zed window (current if no name)
#        gwt ls                 List worktrees
#        gwt rm [-f] [-d|-D] <name>  Remove a worktree (fuzzy name like `cd`; -f/--force skips the prompt;
#                                    -d also deletes its local branch, -D force-deletes an unmerged one)
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
#
# .gwt (worktree-lifecycle hooks):
#   If $repo_root/.gwt exists, it declares commands to run at lifecycle events —
#   the imperative complement to .worktreeinclude's declarative file copying. YAML:
#     hooks:
#       post-add: { run: [dox, setup, --force] }   # after `gwt add` (+ include copy)
#       pre-rm:   { run: dox down }                 # before `gwt rm` tears it down
#   `run` may be a string (split on whitespace) or an explicit argv list. post-add
#   runs in the freshly created worktree; pre-rm runs in the worktree about to be
#   removed (so a stack/stateful resource can be torn down first). Hooks are
#   best-effort: a non-zero exit warns but never aborts the add/rm — a worktree
#   that already exists (or is about to be removed) is not left half-done by a
#   provisioning hiccup. A malformed .gwt is ignored rather than blocking gwt.
#
# Tab completion for the subcommands and worktree names lives in the autoloaded
# zsh/completions/_gwt, alongside the other CLIs' completions.

# The logic lives in lib/gwt.rb (Ruby, unit-tested). A subprocess cannot
# change this shell's directory, so the helper writes the cd target to the file
# named by $GWT_CD_FILE and we cd there on return — the one thing the shell must
# own. Everything else (resolution, fuzzy matching, .worktreeinclude, status)
# is the helper's job.
gwt() {
  local helper="$HOME/dotfiles/lib/gwt.rb"
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
