#!/bin/bash
# Sketchybar workspace indicator — Tokyo Night Storm
# Palette source-of-truth: ~/Code/personal/dotfiles/themes/tokyo-night-storm/palette.sh
# Workspaces 1–6 have a fixed name and always show.
# Workspaces 7–9 show only when they have windows or are focused, named by their apps.

WORKSPACE="$1"
FIXED_NAME="$2"
FOCUSED_WORKSPACE="${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused 2>/dev/null)}"

ARGS=()
if [ -z "$FIXED_NAME" ]; then
  APPS="$(aerospace list-windows --workspace "$WORKSPACE" --format '%{app-name}' 2>/dev/null | sort -u | paste -sd ',' - | sed 's/,/, /g')"
  if [ "$WORKSPACE" != "$FOCUSED_WORKSPACE" ] && [ -z "$APPS" ]; then
    sketchybar --set "$NAME" drawing=off
    exit 0
  fi
  ARGS+=(icon="$WORKSPACE:${APPS:-empty}")
fi

if [ "$WORKSPACE" = "$FOCUSED_WORKSPACE" ]; then
  sketchybar --set "$NAME" drawing=on "${ARGS[@]}" \
    background.drawing=on \
    background.color=0xffe0af68 \
    icon.highlight=on
else
  sketchybar --set "$NAME" drawing=on "${ARGS[@]}" \
    background.drawing=off \
    icon.highlight=off
fi
