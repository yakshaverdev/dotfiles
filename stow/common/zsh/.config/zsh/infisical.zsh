# ─── Infisical multi-account routing ─────────────────────────────
# Two self-hosted Infisical instances ("profiles") are kept logged in via
# `infisical login --domain=...`. Both accounts live in `loggedInUsers`
# inside ~/.infisical/infisical-config.json.
#
# Important: Infisical CLI v0.43 ignores the --domain flag for routing —
# every request is sent to whichever domain matches the file's
# `loggedInUserEmail` + `LoggedInUserDomain`. So we MUST rewrite that
# active-user pointer before each `infisical run` invocation. That's what
# `infisical_set_active_user` below does.
#
# Per-repo opt-in: a repo with `.infisical.json` at its root gets its own
# workspace. Domain comes from the file's `_domain` field if present
# (explicit, recommended); otherwise from cwd-based routing.
#
# Example .infisical.json:
#   {
#     "workspaceId": "0ab0efb3-...",
#     "defaultEnvironment": "prod",
#     "_domain": "https://infisical.akshaydeshraj.me"
#   }
# (Infisical CLI ignores `_domain`; only the wrapper reads it.)
#
# Default workspaceId for repos that don't carry their own config lives in
# `~/.infisical.json`. Its `_domain` field tags WHICH instance owns that
# workspace (workspaceIds are instance-specific). The wrapper falls back
# to this file ONLY when cwd routing agrees with `_domain`; otherwise it
# skips injection rather than 404 against a foreign instance.
#
# Cwd-based domain resolution, highest precedence first:
#   1. $INFISICAL_PROFILE env var (explicit override)
#   2. $PWD under ~/Code/work/*       → skit
#   3. $PWD under ~/Code/personal/*   → personal
#   4. fallback                       → personal
#
# To add a new repo: drop a `.infisical.json` with `workspaceId` and `_domain`
# at its root. To add a new profile: extend _resolve_infisical_domain below
# and `infisical login --domain=<new-url>` once.
#
# If the infisical binary is not installed, every wrapper runs the real tool
# directly — no injection, no errors.
_resolve_infisical_domain() {
  local profile="${INFISICAL_PROFILE:-}"
  if [ -z "$profile" ]; then
    case "$PWD/" in
      $HOME/Code/work/*)     profile=skit ;;
      $HOME/Code/personal/*) profile=personal ;;
      *)                     profile=personal ;;
    esac
  fi
  case "$profile" in
    skit)     echo "https://infisical.skit.ai" ;;
    personal) echo "https://infisical.akshaydeshraj.me" ;;
    *) echo "unknown infisical profile: $profile" >&2; return 1 ;;
  esac
}

# Switch the active Infisical user/domain in ~/.infisical/infisical-config.json
# to the one matching `target_domain` (e.g. https://infisical.skit.ai). This
# is required because Infisical CLI's --domain flag is ignored for routing;
# only the active-user pointer steers requests. Atomic via temp file +
# os.replace. No-op if the target is already active or the config is missing.
# Errors out (and aborts the caller) if the target domain has no logged-in
# user — fix with `infisical login --domain=<target>` once.
infisical_set_active_user() {
  local target_domain="${1%/}"
  local cfg="$HOME/.infisical/infisical-config.json"
  [ -f "$cfg" ] || return 0
  command jq --version >/dev/null 2>&1 || { print -u2 "[infisical-wrapper] jq not found; cannot switch active user"; return 1; }
  local target_api="${target_domain}/api"
  local current_email current_domain
  current_email="$(command jq -r '.loggedInUserEmail // ""' "$cfg" 2>/dev/null)"
  current_domain="$(command jq -r '.LoggedInUserDomain // ""' "$cfg" 2>/dev/null)"
  if [ "$current_domain" = "$target_api" ] && [ -n "$current_email" ]; then
    return 0
  fi
  local target_email
  target_email="$(command jq -r --arg d "$target_api" '.loggedInUsers[]? | select(.domain == $d) | .email' "$cfg" 2>/dev/null | command head -1)"
  if [ -z "$target_email" ]; then
    print -u2 "[infisical-wrapper] no logged-in user for $target_domain — run: infisical login --domain=$target_domain"
    return 2
  fi
  local tmp
  tmp="$(command mktemp "$cfg.XXXXXX")" || return 1
  if ! command jq --arg email "$target_email" --arg domain "$target_api" \
        '.loggedInUserEmail = $email | .LoggedInUserDomain = $domain' \
        "$cfg" > "$tmp"; then
    command rm -f "$tmp"
    return 1
  fi
  command mv -f "$tmp" "$cfg" || { command rm -f "$tmp"; return 1; }
}

# Resolve the directory holding .infisical.json. The CLI only reads it from
# the path passed via --project-config-dir (or cwd as a fallback), so for
# repo subdirs we walk up to the git toplevel.
_resolve_project_config_dir() {
  git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD"
}

# Read the optional `_domain` field out of a .infisical.json. Infisical CLI
# ignores unknown fields, so this is safe to embed alongside workspaceId.
# Echoes empty string if the field is missing or the file is malformed.
# Uses `command grep` to bypass the user's grep→rg alias.
_extract_infisical_domain_override() {
  local file="$1"
  [ -f "$file" ] || return 0
  command grep -oE '"_domain"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" 2>/dev/null \
    | command sed -E 's/.*"_domain"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' \
    | command head -1
}

# Run $tool inside `infisical run` when a project config is available.
# Otherwise (or when infisical is missing) run the real binary untouched.
_run_project_agent() {
  setopt local_options local_traps
  local tool="$1"
  shift
  local bin
  bin="$(whence -p "$tool")" || { print -u2 "[infisical-wrapper] $tool not found"; return 127; }

  local config_dir domain="" domain_source="" skip_injection=0
  config_dir="$(_resolve_project_config_dir)"

  # If the repo doesn't carry its own .infisical.json, fall back to the
  # home-level default (~/.infisical.json) for workspaceId — but only if
  # cwd routing agrees with the home file's `_domain` tag. Otherwise the
  # home workspace lives in a different Infisical instance than where
  # we'd route, so injection would 404. In that case skip injection.
  if [[ ! -f "$config_dir/.infisical.json" ]] && [[ -f "$HOME/.infisical.json" ]]; then
    local home_domain cwd_domain
    home_domain="$(_extract_infisical_domain_override "$HOME/.infisical.json")"
    cwd_domain="$(_resolve_infisical_domain)" || return $?
    if [[ -z "$home_domain" ]] || [[ "${home_domain%/}" == "${cwd_domain%/}" ]]; then
      config_dir="$HOME"
      domain="$cwd_domain"
      domain_source="cwd-resolver+home-fallback"
    else
      skip_injection=1
      [[ -n "${INFISICAL_DEBUG:-}" ]] && print -u2 "[infisical-wrapper] home workspace tagged $home_domain but cwd routes to $cwd_domain — skipping injection"
    fi
  fi

  if (( skip_injection )) || [[ ! -f "$config_dir/.infisical.json" ]]; then
    [[ -n "${INFISICAL_DEBUG:-}" ]] && (( ! skip_injection )) && print -u2 "[infisical-wrapper] no .infisical.json — running $tool without injection"
    "$bin" "$@"
    return $?
  fi

  if [[ -z "$domain" ]]; then
    domain="$(_extract_infisical_domain_override "$config_dir/.infisical.json")"
    domain_source="file"
    if [[ -z "$domain" ]]; then
      domain_source="cwd-resolver"
      domain="$(_resolve_infisical_domain)" || return $?
    fi
  fi
  [[ -n "${INFISICAL_DEBUG:-}" ]] && print -u2 "[infisical-wrapper] config_dir=$config_dir domain=$domain (source=$domain_source)"

  if ! (( $+commands[infisical] )); then
    [[ -n "${INFISICAL_DEBUG:-}" ]] && print -u2 "[infisical-wrapper] infisical not installed — running $tool directly"
    "$bin" "$@"
    return $?
  fi

  infisical_set_active_user "$domain" || return $?
  infisical run --domain="$domain" --project-config-dir="$config_dir" --env=prod --silent -- "$bin" "$@"
}

unalias claude 2>/dev/null
claude() {
  local args=(--dangerously-skip-permissions)
  [[ "$OSTYPE" == darwin* ]] && args+=(--chrome)
  if [ -d .claude/conversations ]; then
    args+=(--continue)
  fi
  _run_project_agent claude "${args[@]}" "$@"
}

unalias codex 2>/dev/null
codex() {
  _run_project_agent codex --dangerously-bypass-approvals-and-sandbox "$@"
}

unalias pi 2>/dev/null
pi() {
  _run_project_agent pi "$@"
}

# AWS CLI — credentials injected from Infisical (work account).
# Project ID lives in ~/.aws/.infisical.json; domain is fixed since AWS
# creds only exist in the work instance regardless of cwd. The
# infisical_set_active_user call is required because the CLI's --domain
# flag is decorative; routing follows the active user in
# ~/.infisical/infisical-config.json.
unalias aws 2>/dev/null
aws() {
  if ! (( $+commands[infisical] )); then
    command aws "$@"
    return
  fi
  infisical_set_active_user https://infisical.skit.ai || return $?
  infisical run --domain=https://infisical.skit.ai --project-config-dir="$HOME/.aws" --env=prod --silent --log-level=warn -- command aws "$@"
}
