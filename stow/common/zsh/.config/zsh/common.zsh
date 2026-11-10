# ─── Shared zsh configuration (macOS + Linux) ────────────────────
# Sourced by ~/.zshrc. OS-specific settings live in darwin.zsh /
# linux.zsh; secrets live in ~/.env and ~/.config/zsh/local.zsh.

# ─── Tokyo Night Storm palette (single source of truth) ──────────
# Exports $TN_BG, $TN_FG, $TN_RED, etc. Used below for fzf, syntax
# highlighting, autosuggestions. App-side configs (ghostty, tmux,
# btop, sketchybar, etc.) hardcode the same hex with a comment
# pointing back to palette.sh.
[[ -f "$DOTFILES/themes/tokyo-night-storm/palette.sh" ]] && \
  source "$DOTFILES/themes/tokyo-night-storm/palette.sh"

# ─── Dedupe key arrays (must come before any appends) ─────────────
# Auto-reload below re-sources ~/.zshrc, so anything mutated additively
# (path/fpath/precmd_functions) would accumulate without these.
typeset -U path fpath
typeset -aU precmd_functions

# ─── Auto-reload zshrc when modified ──────────────────────────────
# zsh/stat's zstat is portable (BSD stat -f is not); watch the resolved
# real file so edits to the stowed source trigger a reload too.
zmodload -F zsh/stat b:zstat 2>/dev/null
_ZSHRC_REAL="${${:-$HOME/.zshrc}:A}"
_ZSHRC_MTIME=$(zstat +mtime -- "$_ZSHRC_REAL" 2>/dev/null)
_check_zshrc_reload() {
  local mtime
  mtime=$(zstat +mtime -- "$_ZSHRC_REAL" 2>/dev/null)
  if [[ "$mtime" != "$_ZSHRC_MTIME" ]]; then
    _ZSHRC_MTIME=$mtime
    source ~/.zshrc
  fi
}
precmd_functions+=(_check_zshrc_reload)

# ─── History Configuration ──────────────────────────────────────
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=1000000000
export SAVEHIST=$HISTSIZE
setopt EXTENDED_HISTORY          # Timestamps in history
setopt HIST_IGNORE_ALL_DUPS      # No duplicate entries
setopt HIST_FIND_NO_DUPS         # Skip duplicates in search
setopt SHARE_HISTORY             # Share history across sessions (implies INC_APPEND_HISTORY)
setopt HIST_IGNORE_SPACE         # Commands starting with space aren't recorded
setopt HIST_REDUCE_BLANKS        # Remove extra whitespace

# ─── Useful Shell Options ───────────────────────────────────────
setopt autocd                    # cd by typing directory name
setopt correct                   # Spelling correction for commands
setopt interactive_comments      # Allow comments in interactive shell
setopt no_beep                   # Disable terminal beep

# ─── PATH Configuration (portable entries, deduped) ─────────────
# OS-specific entries are prepended in darwin.zsh / linux.zsh.
path=(
  "$HOME/.local/bin"
  "$HOME/.cargo/bin"
  "$HOME/go/bin"
  "$HOME/.bun/bin"
  "$HOME/.opencode/bin"
  "$HOME/.npm-global/bin"
  $path
)
export BUN_INSTALL="$HOME/.bun"

# ─── Cached eval helper ────────────────────────────────────────
# Caches output of slow "tool init zsh" commands. Auto-invalidates when the
# binary is newer than the cache (e.g. after brew upgrade). Usage:
#   _cached_eval <name> <binary> <command to generate shell code...>
# Returns 1 when the binary is missing; callers below use `|| true`.
_zsh_cache_dir="$HOME/.zsh/cache"
[[ -d "$_zsh_cache_dir" ]] || mkdir -p "$_zsh_cache_dir"
_cached_eval() {
  local name="$1" bin_path="${commands[$2]:-}"; shift 2
  [[ -z "$bin_path" ]] && return 1
  local cache_file="$_zsh_cache_dir/$name.zsh"
  if [[ ! -f "$cache_file" || "$bin_path" -nt "$cache_file" ]]; then
    eval "$@" > "$cache_file" 2>/dev/null
  fi
  source "$cache_file"
}

# ─── Completion System (with caching) ────────────────────────────
fpath=("$HOME/.zsh/completion" $fpath)
# grok installer completions — added before compinit so they get picked up.
[[ -d "$HOME/.grok/completions/zsh" ]] && fpath=("$HOME/.grok/completions/zsh" $fpath)
autoload -Uz compinit
# Only initialize once per shell: re-running compinit on every zshrc reload
# re-audits fpath and can abort (or prompt) if a directory is group-writable.
if ! (( $+functions[compdef] )); then
  if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
    compinit
  else
    compinit -C  # Use cached completions (much faster)
  fi
fi

# ─── Prompt ───────────────────────────────────────────────────────
# Starship reads ~/.config/starship.toml (Tokyo Night Storm).
_cached_eval starship starship 'starship init zsh' || true

# ─── Eager-load mise (manages Python, Node, and more) ───────────
# Eagerly activated so shebang scripts (e.g. #!/usr/bin/env node) resolve
# through mise shims via raw PATH — lazy-load wouldn't fire for those.
# _sfw_wrap runs later (below) and overlays sfw on top of mise's shims.
if [[ -o interactive ]]; then
  if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate zsh)"
  elif [[ -x "$HOME/.local/bin/mise" ]]; then
    eval "$("$HOME/.local/bin/mise" activate zsh)"
  fi
fi

# ─── Lazy-load direnv (loads on first cd) ────────────────────────
_direnv_hook() {
  unset -f _direnv_hook
  if command -v direnv >/dev/null 2>&1; then
    eval "$(direnv hook zsh)"
    _direnv_hook
  fi
}
precmd_functions+=(_direnv_hook)

# ─── fzf Fuzzy Finder Integration ────────────────────────────────
# Ctrl+R: fuzzy history search | Ctrl+T: fuzzy file search | Alt+C: fuzzy cd
# Colors derived from $TN_* via tn_fzf_colors helper (palette.sh).
if (( $+functions[tn_fzf_colors] )); then
  export FZF_DEFAULT_OPTS="--color=$(tn_fzf_colors)"
fi
_cached_eval fzf fzf 'fzf --zsh' || true

# Keep arrow keys for simple prefix search (works alongside fzf)
autoload -U history-search-end
zle -N history-beginning-search-backward-end history-search-end
zle -N history-beginning-search-forward-end history-search-end
bindkey "^[[A" history-beginning-search-backward-end
bindkey "^[[B" history-beginning-search-forward-end

# ─── Modern CLI Replacements ──────────────────────────────────────
# Zoxide - smarter cd that learns your habits
_cached_eval zoxide zoxide 'zoxide init zsh' || true

# bat: TN Storm tmTheme lives in dotfiles bat/ stow package. Rebuild after
# tmTheme edits with: bat cache --build
export BAT_THEME="tokyo-night-storm"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"

# ─── eza colors ───────────────────────────────────────────────────
# Truecolor (24-bit) RGB derived from $TN_* via tn_eza_colors helper
# (palette.sh). Covers files, perms, ownership, sizes, dates, and git.
if (( $+functions[tn_eza_colors] )); then
  export EZA_COLORS="$(tn_eza_colors)"
fi

# ─── Atuin - Better Shell History ─────────────────────────────────
# Syncs history across devices, better search UI (Ctrl+R)
_cached_eval atuin atuin 'atuin init zsh --disable-up-arrow' || true

# ─── Aliases ─────────────────────────────────────────────────────
# Skipped in agent shells (see DOT_AGENT_SHELL in ~/.zshrc).
if [[ -z "${DOT_AGENT_SHELL:-}" ]]; then
  alias ls='eza --header --group --git --long'
  alias ls.tree='eza --header --group --tree --level=2 --git --long --icons'
  alias ll='eza --header --group --long --all'
  alias ll.tree='eza --header --group --tree --level=2 --git --long --icons --all'
  alias cat='bat --paging=never'
  # Guarded: grep is used by zsh's own completion setup on re-source, so an
  # alias to a not-yet-installed rg would abort compinit on a fresh machine.
  (( $+commands[rg] )) && alias grep='rg'
  alias du='dust'
  alias top='btop'
  alias diff='delta'
fi

# ─── solve: one-shot init + compile + run for competitive programming ────
# Usage:
#   solve init             # copies <repo-root>/template.cpp → ./solution.cpp
#                          # (refuses to overwrite if solution.cpp already exists)
#   solve                  # compiles ./solution.cpp, runs with ./input.txt if present
#   solve foo.cpp          # compiles foo.cpp → ./foo, runs with ./input.txt if present
#   solve foo.cpp in.txt   # runs ./foo with in.txt as stdin
#
# Prefers clang++ (working ASan/UBSan + bits/stdc++.h via the repo's .lsp/
# shim). Falls back to g++-N where GCC's sanitizers and <bits/stdc++.h> work
# natively.
# Uses gnu++20, -O2, sanitizers, -DLOCAL (so `#ifdef LOCAL` debug code fires).
solve() {
  emulate -L zsh

  # `solve init` — scaffold solution.cpp from the repo's template.cpp.
  if [[ "$1" == init ]]; then
    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    if [[ -z "$repo_root" || ! -f "$repo_root/template.cpp" ]]; then
      print -u2 "solve init: no template.cpp at git repo root"
      return 1
    fi
    if [[ -e solution.cpp ]]; then
      print -u2 "solve init: solution.cpp already exists here — refusing to overwrite"
      return 1
    fi
    cp "$repo_root/template.cpp" solution.cpp
    print "solve init: created ./solution.cpp from $repo_root/template.cpp"
    return 0
  fi

  local src="${1:-solution.cpp}"
  if [[ ! -f "$src" ]]; then
    print -u2 "solve: $src not found (run 'solve init' to scaffold it)"
    return 1
  fi
  local out="${src:r}"
  local input_file="${2:-input.txt}"

  local compiler=
  if command -v clang++ >/dev/null 2>&1; then
    compiler=clang++
  else
    for v in 15 14 13; do
      if command -v g++-$v >/dev/null 2>&1; then
        compiler=g++-$v
        break
      fi
    done
  fi
  if [[ -z "$compiler" ]]; then
    print -u2 "solve: no C++ compiler found (need clang++ or g++-{13,14,15})"
    return 1
  fi

  local -a flags=(
    -std=gnu++20 -O2 -Wall -Wextra -Wshadow
    -fsanitize=address,undefined
    -DLOCAL
  )

  # clang++ lacks <bits/stdc++.h> on macOS; pull the shim from the repo's .lsp/.
  if [[ "$compiler" == clang++ ]]; then
    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    [[ -n "$repo_root" && -d "$repo_root/.lsp" ]] && flags+=(-I"$repo_root/.lsp")
  fi

  "$compiler" "${flags[@]}" "$src" -o "$out" || return $?

  if [[ -f "$input_file" ]]; then
    "./$out" < "$input_file"
  else
    "./$out"
  fi
}

# ─── Supply chain: 7-day release cooldown ────────────────────────
# Blocks any package version published <7d ago. Most malicious releases
# are caught within 24-48h (axios, litellm, pytorch-lightning attacks
# would all have been blocked). Pairs with sfw (socket malware scan)
# below for defense in depth.
#   - uv:   reads UV_EXCLUDE_NEWER env var (this line)
#   - npm:  ~/.npmrc            min-release-age=7
#   - pnpm: ~/.config/pnpm/rc   minimumReleaseAge=10080
#   - pip:  --uploaded-prior-to flag injected by _sfw_wrap below
#   - cargo: no clean integration with sfw; install cargo-cooldown
#     manually if needed (`cargo install cargo-cooldown`).
# Override for urgent CVE patches: UV_EXCLUDE_NEWER= cmd ...
# BSD date (-v) and GNU date (-d) take different relative-date flags.
_days_ago_iso() {
  date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}
export UV_EXCLUDE_NEWER="$(_days_ago_iso)"

# ─── sfw — safe package install wrappers ─────────────────────────
# Routes install/add commands through sfw; passthrough for everything else.
# Only defined when sfw is actually installed (mise npm:sfw).
_sfw_wrap() {
  command -v sfw >/dev/null 2>&1 || return 0
  # Most tools: just route install/add through sfw. Cooldown is enforced
  # via env var (uv) or per-tool config files (npm/pnpm).
  for _cmd in npm yarn pnpm uv cargo; do
    eval "
      ${_cmd}() {
        case \"\$1\" in
          install|add|i) command sfw ${_cmd} \"\$@\" ;;
          *)             command ${_cmd} \"\$@\" ;;
        esac
      }
    "
  done
  # pip lacks a config-file equivalent for relative durations, so inject
  # --uploaded-prior-to on each install call (recomputed dynamically).
  for _cmd in pip pip3; do
    eval "
      ${_cmd}() {
        case \"\$1\" in
          install)
            local _cd=\$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)
            command sfw ${_cmd} \"\$@\" --uploaded-prior-to \"\$_cd\"
            ;;
          *) command ${_cmd} \"\$@\" ;;
        esac
      }
    "
  done
  unset _cmd
}
_sfw_wrap
