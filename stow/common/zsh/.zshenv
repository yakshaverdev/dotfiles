# ─── ~/.zshenv: read by every zsh, including non-interactive ones ─
# (agent commands, `ssh host cmd`, scripts). Keep it small, silent and
# never failing.

# ~/.local/bin (dots, claude-ctx, standalone codex and claude) for every
# shell, including `ssh host cmd`. Appended, so it never shadows Homebrew.
[[ -d "$HOME/.local/bin" ]] && path=($path "$HOME/.local/bin")

# mise shims, so non-interactive shells (ssh commands, T3 device hosts)
# find node/npm and other mise tools without ~/.zshrc.
[[ -d "$HOME/.local/share/mise/shims" ]] && path=("$HOME/.local/share/mise/shims" $path)

# Route every `claude` call through claude-ctx (<repo>/bin/shims/claude).
# Keep it first, ahead of the mise shims. ~/.zshenv is stowed from
# <repo>/stow/common/zsh/.zshenv, so :A resolves the symlink and four :h
# modifiers climb back up to <repo>.
if [[ -z ${DOTS_SHIM_DIR:-} ]]; then
  export DOTS_SHIM_DIR="${DOTFILES:-${${:-$HOME/.zshenv}:A:h:h:h:h}}/bin/shims"
fi
if [[ -d ${DOTS_SHIM_DIR:-} ]]; then
  path=($DOTS_SHIM_DIR $path)
  typeset -U path
fi

# Personal secrets from Infisical (written by `dots secret sync`).
[[ -r "$HOME/.config/dot/secrets.zsh" ]] && source "$HOME/.config/dot/secrets.zsh"

# Client contexts for agent command shells. Coding agents run each command
# in a non-interactive shell that does not read ~/.zshrc; apply the context
# here so agent commands in a client repo see client values (strict mode
# removes the personal ones loaded above). An inherited DOT_CTX or DOT_CTX_PIN
# also applies the context in a child shell.
if [[ ! -o interactive ]] && \
   [[ -n "${DOT_CTX:-}${DOT_CTX_PIN:-}${CLAUDECODE:-}${T3CODE_THREAD_ID:-}${CODEX_THREAD_ID:-}${CODEX_SANDBOX:-}${OPENCODE:-}" ]]; then
  if [[ -r "$HOME/.config/zsh/contexts.zsh" ]]; then
    source "$HOME/.config/zsh/contexts.zsh" >/dev/null 2>&1
  fi
fi
true
