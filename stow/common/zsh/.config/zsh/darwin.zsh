# ─── macOS-only zsh configuration ────────────────────────────────
# Sourced by ~/.zshrc on darwin.

# ─── Homebrew (Apple Silicon) ────────────────────────────────────
# shellenv prepends Homebrew's bin/sbin, keeping brew-managed tools early
# in PATH so stale bundled copies cannot shadow them.
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

# ─── macOS-only PATH entries ─────────────────────────────────────
export PNPM_HOME="$HOME/Library/pnpm"
path=(
  "/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
  "/Applications/Obsidian.app/Contents/MacOS"
  /opt/homebrew/opt/openjdk/bin
  "$HOME/.antigravity/antigravity/bin"
  "$HOME/.amp/bin"
  "$HOME/.darkbloom/bin"
  "$HOME/Code/sonar-scanner/bin"
  "$PNPM_HOME"
  $path
)

# ─── grok installer ──────────────────────────────────────────────
# Completions fpath is registered in common.zsh before compinit.
path=("$HOME/.grok/bin" $path)

# ─── bun completions ─────────────────────────────────────────────
[[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"

alias gam="$HOME/bin/gam7/gam"

# ─── Donna — chief of staff (custom system prompt) ───────────────
if [[ -r "$HOME/Code/personal/chief-of-staff/900-donna/bin/donna.zsh" ]]; then
  source "$HOME/Code/personal/chief-of-staff/900-donna/bin/donna.zsh"
fi

# ─── SmartClip — auto-fix multi-line commands on paste ───────────
if [[ -r "$HOME/Code/personal/smartclip/integrations/smartclip.zsh" ]]; then
  source "$HOME/Code/personal/smartclip/integrations/smartclip.zsh"
fi

# ─── opam ────────────────────────────────────────────────────────
[[ ! -r "$HOME/.opam/opam-init/init.zsh" ]] || \
  source "$HOME/.opam/opam-init/init.zsh" >/dev/null 2>/dev/null

# ─── C++ (Homebrew g++ with a LOCAL-only debug macro) ────────────
alias cpp='g++-15 -std=gnu++20 -O2 -Wall -DLOCAL'

# ─── serena (MCP servers in Docker) ──────────────────────────────
alias serena-work='docker run --rm -i --network host -v ~/Code/work:/workspaces/projects ghcr.io/oraios/serena:latest serena'
alias serena-personal='docker run --rm -i --network host -v ~/Code/personal:/workspaces/projects ghcr.io/oraios/serena:latest serena'

# ─── Remote hosts (Tailscale MagicDNS names, no IPs) ─────────────
alias vps='TERM=xterm-256color mosh ubuntu@terminator-silver -- tmux new -A -s main'
alias nas='ssh akshaydeshraj@nas'
