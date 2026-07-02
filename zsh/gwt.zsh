# gwt — git worktree helper for .claude/worktrees/. Run `gwt help` for the full
# command list; the design rationale lives in .claude/docs/gwt_worktree_model.md.
#
# The logic is the gwt-bin binary (a Go port of the old lib/gwt.rb). A child
# process can't change this shell's directory, so gwt-bin writes its chosen cd
# target to $GWT_CD_FILE and the wrapper cds there on return — the one thing the
# shell must own. Everything else (resolution, fuzzy matching, .worktreeinclude,
# status) is the binary's job. Tab completion lives in zsh/completions/_gwt.
gwt() {
  local cd_file rc
  cd_file=$(mktemp "${TMPDIR:-/tmp}/gwt-cd.XXXXXX")
  GWT_CD_FILE="$cd_file" "$HOME/.local/bin/gwt-bin" "$@"
  rc=$?
  [[ -s "$cd_file" ]] && cd "$(<"$cd_file")"
  rm -f "$cd_file"
  return $rc
}
