# --- gwt: git worktree helpers for .claude/worktrees/ ---
# Usage: gwt add <branch>       Create worktree and cd into it
#        gwt add -b <branch>    Create branch + worktree and cd into it
#        gwt add -b <new>:<from>  Branch <new> off <from>'s tip (works even if <from>
#                                 is already checked out elsewhere) + worktree
#        gwt sync [<name>|--all] [-f] [-y] [--hooks]  Merge root's .worktreeinclude DOWN
#                               into a worktree. Previews the changes and prompts before
#                               applying; -y skips the prompt, -f makes root win on conflict,
#                               --hooks re-runs post-add. Default target: the current worktree.
#        gwt promote [<name>] [-f] [-y]  Merge a worktree's .worktreeinclude UP into root —
#                               the reverse of sync, for pushing a worktree-local edit back to
#                               the canonical root. Same preview + prompt (-y skips it); -f makes
#                               the worktree win on conflict. Default source: the current worktree.
#        gwt send <path> [--from <src>] [--to <dst>] [-f] [-y]  Copy one ad-hoc path (file or
#                               whole directory, recursively) between endpoints — root or a named
#                               worktree, --from/--to, omitted side defaults to where you are.
#                               Unlike sync/promote it's not tied to .worktreeinclude; it moves
#                               exactly the path you name. Same preview + prompt (-y skips it);
#                               -f makes the source win. Serves the lateral worktree->worktree copy.
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
#       post-add:   { run: [dox, setup, --force] } # after `gwt add` (+ include copy)
#       post-mv:    { run: [dox, setup, --force] } # after `gwt mv` relocates a worktree
#       pre-rm:     { run: dox down }              # before `gwt rm` tears it down
#       pre-prune:  { run: dox down }              # before `gwt prune` removes an orphan dir
#   `run` may be a string (split on whitespace) or an explicit argv list. The four
#   events are explicit and independent — none implies another, so a `gwt mv` fires
#   only post-mv (never post-add), and a project re-uses an action by declaring it
#   under each event it wants. post-add/post-mv run in the new/renamed worktree;
#   pre-rm runs in the worktree about to be removed and pre-prune in each orphaned
#   directory about to be deleted (so a stack/stateful resource is torn down first).
#   Hooks are best-effort: a non-zero exit warns but never aborts the verb — a
#   worktree mid-transition is not left half-done by a provisioning hiccup. A
#   malformed .gwt is ignored rather than blocking gwt.
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
