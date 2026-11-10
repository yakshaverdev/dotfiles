#!/bin/bash
# Homebrew is only present on macOS; prepend it there so fzf/tmux resolve.
if [ -d /opt/homebrew/bin ]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi

CURRENT=$(tmux display-message -p '#S')

# Build session list; ● marks the current session.
session=$(tmux list-sessions -F '#S' 2>/dev/null | while read -r s; do
  marker=""
  [ "$s" = "$CURRENT" ] && marker="  ●"
  echo "${s}${marker}"
done | \
  fzf --reverse --border=none --no-info \
  --print-query \
  --header='  Pick or create a session' \
  --color=bg+:#2e3c64,fg+:#c0caf5,hl:#e0af68,hl+:#e0af68,pointer:#e0af68,prompt:#7aa2f7 \
  | tail -1 | sed 's/  ●.*$//')

if [ -n "$session" ]; then
  if tmux has-session -t "$session" 2>/dev/null; then
    tmux switch-client -t "$session"
  else
    tmux new-session -d -s "$session" && tmux switch-client -t "$session"
  fi
fi
