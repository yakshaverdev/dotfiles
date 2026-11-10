# shellcheck shell=bash
# ─── Client contexts for bash agent command shells ───────────────
# Sourced via BASH_ENV before a non-interactive bash command. Applies the
# context for $PWD so agent commands in a client repo see client values.
#
# Silent, fast, and must never fail the caller. Any shell option changes are
# restored before returning.

_dots_bash_ctx_unset_names() {
  local _f=$1 _n
  [[ -r $_f ]] || return 0
  while IFS= read -r _n || [[ -n $_n ]]; do
    [[ -n $_n ]] || continue
    [[ $_n =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    unset "$_n" 2>/dev/null || true
  done < "$_f"
  return 0
}

_dots_bash_ctx_mode() {
  local _i
  for ((_i = 0; _i < ${#_DOTS_BASH_CTX_NAMES[@]}; _i++)); do
    if [[ ${_DOTS_BASH_CTX_NAMES[_i]} == "$1" ]]; then
      printf '%s' "${_DOTS_BASH_CTX_MODES[_i]}"
      return 0
    fi
  done
  printf 'merge'
}

_dots_bash_ctx_apply() {
  local _markers _line _name _project _mode _patterns _had_e=0 _had_u=0
  local _new=personal _top _url _i _pat _old _mode_old _mode_new _ctxdir
  local -a _pats=()

  # Only agent command shells, and only when non-interactive.
  if [[ $- == *i* ]]; then
    return 0
  fi
  _markers="${CLAUDECODE:-}${T3CODE_THREAD_ID:-}${CODEX_THREAD_ID:-}${CODEX_SANDBOX:-}${OPENCODE:-}"
  if [[ -z $_markers ]]; then
    return 0
  fi

  # Save only the options we change and restore them before returning.
  [[ -o errexit ]] && _had_e=1
  [[ -o nounset ]] && _had_u=1
  set +e +u 2>/dev/null

  # Resolve the repo root from ~/.zshrc (4x dirname) when DOTFILES is unset.
  if [[ -z ${DOTFILES:-} ]]; then
    local _rc="$HOME/.zshrc" _real="" _p _d
    if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
      _real=$(readlink -f "$_rc" 2>/dev/null) || _real=""
    fi
    if [[ -z $_real ]]; then
      _p="$_rc"
      while [[ -L $_p ]]; do
        _d=$(cd -P "$(dirname "$_p")" && pwd 2>/dev/null) || break
        _p=$(readlink "$_p" 2>/dev/null) || break
        [[ $_p == /* ]] || _p="$_d/$_p"
      done
      _d=$(cd -P "$(dirname "$_p")" && pwd 2>/dev/null) || _d=""
      [[ -z $_d ]] || _real="$_d/$(basename "$_p")"
    fi
    if [[ -n $_real ]]; then
      for _i in 1 2 3 4; do _real=$(dirname "$_real"); done
      DOTFILES=$_real
      export DOTFILES
    fi
  fi

  _DOTS_BASH_CTX_NAMES=()
  _DOTS_BASH_CTX_MODES=()
  _DOTS_BASH_CTX_PATTERNS=()
  if [[ -n ${DOTFILES:-} && -r "$DOTFILES/config/contexts" ]]; then
    while IFS= read -r _line || [[ -n $_line ]]; do
      _line=${_line%$'\r'}
      _line="${_line#"${_line%%[![:space:]]*}"}"
      [[ -z $_line || $_line == \#* ]] && continue
      read -r _name _project _mode _patterns <<< "$_line" || continue
      [[ -n $_name && -n $_project ]] || continue
      [[ $_name =~ ^[A-Za-z0-9_-]+$ ]] || continue
      case $_mode in
        strict|merge) ;;
        *) _mode=merge ;;
      esac
      _DOTS_BASH_CTX_NAMES+=("$_name")
      _DOTS_BASH_CTX_MODES+=("$_mode")
      _DOTS_BASH_CTX_PATTERNS+=("${_patterns:-}")
    done < "$DOTFILES/config/contexts"
  fi

  # Detect: git toplevel → origin URL → first matching glob in file order.
  if _top=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null); then
    if _url=$(git -C "$_top" config --get remote.origin.url 2>/dev/null); then
      for ((_i = 0; _i < ${#_DOTS_BASH_CTX_NAMES[@]}; _i++)); do
        _pats=()
        read -r -a _pats <<< "${_DOTS_BASH_CTX_PATTERNS[_i]}" || true
        (( ${#_pats[@]} )) || continue
        for _pat in "${_pats[@]}"; do
          # shellcheck disable=SC2053  # RHS is a deliberate shell glob
          if [[ $_url == $_pat ]]; then
            _new=${_DOTS_BASH_CTX_NAMES[_i]}
            break 2
          fi
        done
      done
    fi
  fi

  _ctxdir="$HOME/.config/dot/ctx"
  _old=${DOT_CTX:-}

  # Drop an inherited context's names, and restore personal values when the
  # old context was strict (matching the zsh hook).
  if [[ -n $_old ]]; then
    _dots_bash_ctx_unset_names "$_ctxdir/$_old.names"
    _mode_old=$(_dots_bash_ctx_mode "$_old")
    if [[ $_mode_old == strict && -r "$HOME/.config/dot/secrets.zsh" ]]; then
      # shellcheck disable=SC1090,SC1091
      source "$HOME/.config/dot/secrets.zsh" 2>/dev/null || true
    fi
  fi

  if [[ $_new == personal ]]; then
    unset DOT_CTX 2>/dev/null || true
    if (( _had_u )); then set -u; fi
    if (( _had_e )); then set -e; fi
    return 0
  fi

  _mode_new=$(_dots_bash_ctx_mode "$_new")
  if [[ $_mode_new == strict ]]; then
    _dots_bash_ctx_unset_names "$HOME/.config/dot/secrets.names"
  fi
  if [[ -r "$_ctxdir/$_new.zsh" ]]; then
    # shellcheck disable=SC1090
    source "$_ctxdir/$_new.zsh" 2>/dev/null || true
  fi
  export DOT_CTX=$_new

  if (( _had_u )); then set -u; fi
  if (( _had_e )); then set -e; fi
  return 0
}

_dots_bash_ctx_apply >/dev/null 2>&1 || true
unset -f _dots_bash_ctx_apply _dots_bash_ctx_mode _dots_bash_ctx_unset_names
unset _DOTS_BASH_CTX_NAMES _DOTS_BASH_CTX_MODES _DOTS_BASH_CTX_PATTERNS
true
