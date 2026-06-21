#!/usr/bin/env bash
# UserPromptSubmit hook: when the user signals they're stepping away / pausing,
# inject a reminder so Claude runs the save-session skill before replying.
#
# Debounced against the jotter log mtime: if a checkpoint/note landed within
# DEBOUNCE_SECS, a save clearly just happened, so the hook stays silent. This
# guards against two walk-away sentences in a row each firing a checkpoint.
#
# Receives the UserPromptSubmit hook payload (JSON) on stdin; emits a JSON
# object whose hookSpecificOutput.additionalContext is added to Claude's context.
# Prints nothing (exit 0) when there's no match or when debounced.

set -euo pipefail

DEBOUNCE_SECS="${WALK_AWAY_DEBOUNCE_SECS:-180}"

# Case-insensitive phrases that mean "I'm stepping away / pausing / continue later".
# Kept tight to avoid false positives (e.g. "off for", "done" deliberately excluded).
WALK_AWAY_RE='when i get back|when i'"'"'?m back|when i return|(lets|let'"'"'s) continue when|continue when i( get| am|'"'"'m)? back|stepping away|step away|back in a (bit|sec|min)|be right back|\bbrb\b|\bbbl\b|taking a break|gonna take a break|heading out|\bafk\b|\bgtg\b|got ?ta go|got to go|call it (a day|here|there)|that'"'"'s it for (now|today)'

payload="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

prompt="$(printf '%s' "$payload" | jq -r '.prompt // empty')"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty')"
[ -n "$prompt" ] || exit 0

# No walk-away signal -> silent.
printf '%s' "$prompt" | grep -iqE "$WALK_AWAY_RE" || exit 0

# Resolve the current jotter session log so we can debounce on its mtime.
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || true
if command -v jotter >/dev/null 2>&1; then
  data_dir="$(jotter config 2>/dev/null | awk -F': ' '/^data_dir:/{print $2}')"
  project="$(jotter project 2>/dev/null || true)"
  branch="$(jotter branch 2>/dev/null || true)"
  # Only meaningful inside a jotter project; otherwise there's no session to save.
  [ -n "$project" ] || exit 0
  if [ -n "$data_dir" ] && [ -n "$branch" ]; then
    log_file="$data_dir/logs/$project/${branch//\//+}.jsonl"
    if [ -f "$log_file" ]; then
      now="$(date +%s)"
      mtime="$(stat -f %m "$log_file" 2>/dev/null || stat -c %Y "$log_file" 2>/dev/null || echo 0)"
      if [ "$mtime" -gt 0 ] && [ $((now - mtime)) -lt "$DEBOUNCE_SECS" ]; then
        exit 0
      fi
    fi
  fi
fi

ctx='The user'"'"'s message suggests they are stepping away or pausing. Before replying, run the save-session skill (WIP-commit dirty work + jotter checkpoint) so the session is left in a walk-away-safe state, then give a brief sign-off. Skip the save only if a checkpoint was very clearly just made this turn.'

jq -cn --arg ctx "$ctx" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
