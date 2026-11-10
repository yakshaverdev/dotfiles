# ─── Source machine-specific secrets ──────────────────────────────
[[ -f "$HOME/.env" ]] && source "$HOME/.env"

# ─── Resolve the repo root from this file's symlink ───────────────
# ~/.zshrc is stowed from <repo>/stow/common/zsh/.zshrc, so :A resolves
# the symlink and four :h modifiers climb back up to <repo>.
export DOTFILES="${DOTFILES:-${${:-$HOME/.zshrc}:A:h:h:h:h}}"

# ─── Agent shells ────────────────────────────────────────────────
# Claude Code, Codex, OpenCode and T3 Code snapshot this config for their
# own shells. Agents need plain tools (grep, cat, ls) and the real CLIs,
# so tool-replacement aliases and the agent wrappers are skipped there.
if [[ -n "${CLAUDECODE:-}${T3CODE_THREAD_ID:-}${CODEX_SANDBOX:-}${CODEX_THREAD_ID:-}${OPENCODE:-}" ]]; then
  export DOT_AGENT_SHELL=1
fi

# ─── Shared configuration (portable) ─────────────────────────────
[[ -f "$HOME/.config/zsh/common.zsh" ]] && source "$HOME/.config/zsh/common.zsh"

# ─── OS-specific configuration ───────────────────────────────────
case "$OSTYPE" in
  darwin*)
    [[ -f "$HOME/.config/zsh/darwin.zsh" ]] && source "$HOME/.config/zsh/darwin.zsh"
    ;;
  linux*)
    [[ -f "$HOME/.config/zsh/linux.zsh" ]] && source "$HOME/.config/zsh/linux.zsh"
    ;;
esac

# ─── Secrets injection (Infisical wrappers) ──────────────────────
[[ -z "${DOT_AGENT_SHELL:-}" && -f "$HOME/.config/zsh/infisical.zsh" ]] && source "$HOME/.config/zsh/infisical.zsh"

# ─── Per-host overrides (e.g. hosts/laptop.zsh) ──────────────────
[[ -f "$HOME/.config/zsh/hosts/${HOST%%.*}.zsh" ]] && \
  source "$HOME/.config/zsh/hosts/${HOST%%.*}.zsh"

# ─── Machine-local, untracked overrides ──────────────────────────
# Installer-added PATH lines belong here so they never churn the repo.
[[ -f "$HOME/.config/zsh/local.zsh" ]] && source "$HOME/.config/zsh/local.zsh"

# ─── Plugins (must be last) ──────────────────────────────────────
[[ -f "$HOME/.config/zsh/plugins.zsh" ]] && source "$HOME/.config/zsh/plugins.zsh"
