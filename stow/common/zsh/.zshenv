# ─── ~/.zshenv: read by every zsh, including non-interactive ones ─
# (agent commands, `ssh host cmd`, scripts). Keep it small, silent and
# never failing.

# mise shims, so non-interactive shells (ssh commands, T3 device hosts)
# find node/npm and other mise tools without ~/.zshrc.
[[ -d "$HOME/.local/share/mise/shims" ]] && path=("$HOME/.local/share/mise/shims" $path)

# Personal secrets from Infisical (written by `dots secret sync`).
[[ -r "$HOME/.config/dot/secrets.zsh" ]] && source "$HOME/.config/dot/secrets.zsh"

# Client contexts for agent command shells. Coding agents run each command
# in a non-interactive shell that does not read ~/.zshrc; apply the context
# here so agent commands in a client repo see client values (strict mode
# removes the personal ones loaded above).
if [[ ! -o interactive ]] && \
   [[ -n "${CLAUDECODE:-}${T3CODE_THREAD_ID:-}${CODEX_THREAD_ID:-}${CODEX_SANDBOX:-}${OPENCODE:-}" ]]; then
  if [[ -r "$HOME/.config/zsh/contexts.zsh" ]]; then
    source "$HOME/.config/zsh/contexts.zsh" >/dev/null 2>&1
  fi
fi
true
