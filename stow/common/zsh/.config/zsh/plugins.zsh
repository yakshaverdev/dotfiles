# ─── Zsh Plugins (must be sourced last) ──────────────────────────
# Autosuggestions: fish-like suggestions as you type (TN dim border).
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=${TN_DIM}"
for _plugins_file in \
  /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /opt/homebrew/opt/zsh-autosuggestions/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh; do
  if [[ -r "$_plugins_file" ]]; then
    source "$_plugins_file"
    break
  fi
done

# Syntax highlighting: colors commands (Tokyo Night Storm palette).
for _plugins_file in \
  /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /opt/homebrew/opt/zsh-syntax-highlighting/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
  if [[ -r "$_plugins_file" ]]; then
    source "$_plugins_file"
    break
  fi
done
unset _plugins_file

# Only touch the styles when the plugin actually loaded (it declares the
# assoc array); otherwise these assignments error on a bare system.
if [[ ${(t)ZSH_HIGHLIGHT_STYLES} == association* ]]; then
  ZSH_HIGHLIGHT_STYLES[command]="fg=${TN_GREEN},bold"
  ZSH_HIGHLIGHT_STYLES[builtin]="fg=${TN_GREEN},bold"
  ZSH_HIGHLIGHT_STYLES[alias]="fg=${TN_GREEN},bold"
  ZSH_HIGHLIGHT_STYLES[function]="fg=${TN_GREEN},bold"
  ZSH_HIGHLIGHT_STYLES[unknown-token]="fg=${TN_RED}"
  ZSH_HIGHLIGHT_STYLES[path]="fg=${TN_CYAN},underline"
  ZSH_HIGHLIGHT_STYLES[globbing]="fg=${TN_MAGENTA}"
  ZSH_HIGHLIGHT_STYLES[single-quoted-argument]="fg=${TN_YELLOW}"
  ZSH_HIGHLIGHT_STYLES[double-quoted-argument]="fg=${TN_YELLOW}"
  ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]="fg=${TN_YELLOW}"
  ZSH_HIGHLIGHT_STYLES[commandseparator]="fg=${TN_ORANGE}"
  ZSH_HIGHLIGHT_STYLES[redirection]="fg=${TN_MAGENTA}"
  ZSH_HIGHLIGHT_STYLES[comment]="fg=${TN_DIM}"
  ZSH_HIGHLIGHT_STYLES[arg0]="fg=${TN_BLUE}"
fi
