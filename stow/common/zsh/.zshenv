# ─── Client contexts for agent command shells ────────────────────
# Coding agents run each command in a non-interactive shell, which does not
# read ~/.zshrc. Apply contexts here so agent commands in a client repo see
# client values instead of the personal environment inherited from T3.
#
# This file must stay silent and must never fail the command.

if [[ ! -o interactive ]] && \
   [[ -n "${CLAUDECODE:-}${T3CODE_THREAD_ID:-}${CODEX_THREAD_ID:-}${CODEX_SANDBOX:-}${OPENCODE:-}" ]]; then
  if [[ -r "$HOME/.config/zsh/contexts.zsh" ]]; then
    source "$HOME/.config/zsh/contexts.zsh" >/dev/null 2>&1
  fi
fi
true
