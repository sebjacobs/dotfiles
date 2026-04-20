#!/usr/bin/env bash
# Claude Code statusLine script
# Mirrors the default Starship prompt: folder, git branch, model, context usage

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

# Build output
out=""

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
