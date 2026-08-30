#!/usr/bin/env bash
# Claude Code statusLine script
# Mirrors the default Starship prompt: gwt slot, folder, git branch, model, context usage

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
folder=$(basename "$cwd")
model=$(echo "$input" | jq -r '.model.display_name // ""')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Git branch (skip lock files to avoid contention with running git ops)
branch=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" -c gc.auto=0 symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$cwd" -c gc.auto=0 rev-parse --short HEAD 2>/dev/null)
fi

# gwt slot number, matching the starship prompt's worktree_slot module: shown
# only inside a linked worktree, where the git-dir and git-common-dir diverge.
# At the root the number is always 0, so the guard buys a quieter line and one
# fewer process spawned per render.
slot=""
if [ -n "$cwd" ] \
   && [ "$(git -C "$cwd" rev-parse --git-dir 2>/dev/null)" \
        != "$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)" ]; then
  slot=$(cd "$cwd" && "$HOME/.local/bin/gwt-bin" slot 2>/dev/null)
fi

# Build output
out=""

# Slot (bold yellow), if inside a worktree
if [ -n "$slot" ]; then
  printf "\033[1;33m[%s]\033[0m " "$slot"
fi

# Folder (cyan)
printf "\033[36m%s\033[0m" "$folder"

# Branch (green), if present
if [ -n "$branch" ]; then
  printf " \033[32m%s\033[0m" "$branch"
fi

# Model (magenta)
if [ -n "$model" ]; then
  printf " \033[35m%s\033[0m" "$model"
fi

# Context remaining (value yellow normally, red when low)
if [ -n "$remaining" ]; then
  remaining_int=$(printf "%.0f" "$remaining")
  if [ "$remaining_int" -le 25 ]; then
    printf " ctx: \033[1;31m%s%%\033[0m" "$remaining_int"
  else
    printf " ctx: \033[33m%s%%\033[0m" "$remaining_int"
  fi
fi

echo ""
