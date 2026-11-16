# Default flags for agent CLIs in interactive shells. Secrets come from
# ~/.config/dot (dots secret) and client contexts, not from these wrappers.
unalias claude codex 2>/dev/null
claude() {
  local args=(--dangerously-skip-permissions)
  [[ "$OSTYPE" == darwin* ]] && args+=(--chrome)
  [[ -d .claude/conversations ]] && args+=(--continue)
  command claude "${args[@]}" "$@"
}
codex() { command codex --dangerously-bypass-approvals-and-sandbox "$@"; }
