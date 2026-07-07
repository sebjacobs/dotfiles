# osc7.zsh — announce the working directory to the terminal on every cd.
#
# Neither starship nor iTerm shell integration (not installed here) emits OSC 7,
# so iTerm can only guess our directory by inspecting the shell process. That
# guess lags and misses cd's made inside wrapper functions like proj/gwt, so
# "Reuse previous session's directory" opens new tabs in a stale directory.
# Emitting OSC 7 from the chpwd hook makes it deterministic for every cd —
# wrappers included — in any OSC 7-aware terminal.
_osc7_emit_cwd() {
  [[ -t 1 ]] || return
  printf '\e]7;file://%s%s\e\\' "$HOST" "$PWD"
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _osc7_emit_cwd
_osc7_emit_cwd
