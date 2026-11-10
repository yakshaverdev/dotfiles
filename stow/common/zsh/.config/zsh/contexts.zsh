# ─── Client context switching ────────────────────────────────────
# Applies ~/.config/dot/ctx/<name>.zsh based on the git origin of $PWD.
# Pure zsh + git; no call into the dots CLI (keeps chpwd fast and silent).

if [[ -z ${DOTFILES:-} ]]; then
  export DOTFILES="${${:-$HOME/.zshrc}:A:h:h:h:h}"
fi

typeset -gA _dots_ctx_cache      # git toplevel (or :none:) → context name
typeset -ga _dots_ctx_names
typeset -ga _dots_ctx_modes
typeset -ga _dots_ctx_patterns

_dots_ctx_load() {
  local line
  local -a fields
  _dots_ctx_names=()
  _dots_ctx_modes=()
  _dots_ctx_patterns=()
  [[ -r "$DOTFILES/config/contexts" ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z $line || $line == \#* ]] && continue
    fields=(${=line})
    (( ${#fields} >= 3 )) || continue
    [[ ${fields[1]} == *[!A-Za-z0-9_-]* ]] && continue
    _dots_ctx_names+=("${fields[1]}")
    _dots_ctx_modes+=("${fields[3]}")
    _dots_ctx_patterns+=("${(j: :)fields[4,-1]}")
  done < "$DOTFILES/config/contexts"
}

_dots_ctx_detect() {
  local dir=${1:-$PWD} top url key pat
  local i
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || top=""
  key=${top:-:none:}
  if (( ${+_dots_ctx_cache[$key]} )); then
    REPLY=${_dots_ctx_cache[$key]}
    return 0
  fi
  if [[ -z $top ]]; then
    _dots_ctx_cache[$key]=personal
    REPLY=personal
    return 0
  fi
  url=$(git -C "$top" config --get remote.origin.url 2>/dev/null) || url=""
  if [[ -z $url ]]; then
    _dots_ctx_cache[$key]=personal
    REPLY=personal
    return 0
  fi
  for ((i = 1; i <= ${#_dots_ctx_names}; i++)); do
    for pat in ${=_dots_ctx_patterns[i]}; do
      if [[ $url == ${~pat} ]]; then
        _dots_ctx_cache[$key]=${_dots_ctx_names[i]}
        REPLY=${_dots_ctx_names[i]}
        return 0
      fi
    done
  done
  _dots_ctx_cache[$key]=personal
  REPLY=personal
}

_dots_ctx_mode() {
  local i
  for ((i = 1; i <= ${#_dots_ctx_names}; i++)); do
    if [[ ${_dots_ctx_names[i]} == "$1" ]]; then
      print -r -- "${_dots_ctx_modes[i]}"
      return 0
    fi
  done
  print -r -- merge
}

_dots_ctx_unset_names() {
  local f=$1 n
  [[ -r $f ]] || return 0
  while IFS= read -r n || [[ -n $n ]]; do
    [[ -n $n ]] || continue
    unset "$n" 2>/dev/null
  done < "$f"
  return 0
}

_dots_ctx_apply() {
  local old=${DOT_CTX:-personal} new new_zsh
  _dots_ctx_detect "$PWD"
  new=$REPLY
  [[ $new == $old ]] && return 0

  if [[ $old != personal ]]; then
    _dots_ctx_unset_names "$HOME/.config/dot/ctx/$old.names"
    if [[ $(_dots_ctx_mode "$old") == strict && -r "$HOME/.config/dot/secrets.zsh" ]]; then
      source "$HOME/.config/dot/secrets.zsh"
    fi
  fi

  if [[ $new == personal ]]; then
    unset DOT_CTX
    return 0
  fi

  if [[ $(_dots_ctx_mode "$new") == strict ]]; then
    _dots_ctx_unset_names "$HOME/.config/dot/secrets.names"
  fi
  new_zsh="$HOME/.config/dot/ctx/$new.zsh"
  [[ -r $new_zsh ]] && source "$new_zsh"
  export DOT_CTX=$new
  return 0
}

_dots_ctx_load
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _dots_ctx_apply

# At load, ~/.zshrc has just sourced the personal secrets.zsh again. A child
# shell (or a zshrc reload) can inherit DOT_CTX and that context's values, so
# drop both and apply the context fresh. Otherwise strict mode would see "no
# change" and leave personal keys visible inside a client repo.
if [[ -n ${DOT_CTX:-} ]]; then
  _dots_ctx_unset_names "$HOME/.config/dot/ctx/$DOT_CTX.names"
  unset DOT_CTX
fi
_dots_ctx_apply 2>/dev/null
