# Login-shell setup. Keep this minimal: ~/.zshrc (via ~/.config/zsh/*)
# does the real work. Only the macOS Homebrew bootstrap belongs here, and
# it is a no-op on Linux.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
