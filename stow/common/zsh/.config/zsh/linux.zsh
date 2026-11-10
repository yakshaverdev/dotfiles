# ─── Linux-only zsh configuration ────────────────────────────────
# Sourced by ~/.zshrc on linux.

# ─── pnpm ────────────────────────────────────────────────────────
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac

# ─── Debian/Ubuntu binary names ──────────────────────────────────
# Only alias when mise/Homebrew hasn't provided the canonical name.
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
  alias bat=batcat
fi
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
  alias fd=fdfind
fi
