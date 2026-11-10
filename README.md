# dotfiles

Personal dev environment for two machines:

- **macOS laptop** (Apple Silicon, Homebrew at `/opt/homebrew`) — AeroSpace,
  SketchyBar, Ghostty, Zed, tmux, zsh.
- **Ubuntu 24.04 VPS** (x86_64, no Homebrew) — tmux, zsh, CLI tooling, systemd.

Configs are symlinked into `$HOME` with [GNU Stow](https://www.gnu.org/software/stow/).
CLI tools and runtimes are installed with [mise](https://mise.jdx.dev/).

## Quick start

```bash
git clone https://github.com/yakshaverdev/dotfiles ~/Code/personal/dotfiles
cd ~/Code/personal/dotfiles
cp .env.example ~/.env && $EDITOR ~/.env   # fill in real values
./bootstrap
```

`bootstrap` installs the minimum needed to run the CLI (Xcode CLT + Homebrew +
`stow jq` on macOS; `stow jq git curl` via apt on Linux), then hands off to
`dots install`.

## Layout

```
bin/dots                 # cross-platform CLI (install / doctor / t3 / secret)
bin/dots-secret          # env var + API key manager (Infisical)
bootstrap               # first-run entry point
config/contexts         # client name → Infisical project + git remote patterns
config/hosts            # machine → ssh target for peer secret sync
hooks/pre-commit        # gitleaks secret scan
packages/Brewfile       # macOS packages
packages/apt.txt        # Linux packages (one per line, # comments)
scripts/macos-defaults.sh
themes/tokyo-night-storm/palette.sh
wallpapers/generate.sh  # regenerates the (gitignored) PNGs
zen/link-profile.sh
t3/                     # portable T3 Code settings (keybindings + base settings)

stow/common/<pkg>       # both OSes: atuin bat btop claude gh git mise pnpm
                        #            prompt tmux zsh
stow/darwin/<pkg>       # macOS only: ghostty launchd wm zed
stow/linux/<pkg>        # Linux only: systemd
```

Each package mirrors a path under `$HOME`:

```bash
stow --no-folding -d "$DOTFILES/stow/<group>" -t "$HOME" <pkg>
```

## `dots` commands

| Command | What it does |
|---|---|
| `dots install` | Idempotent bootstrap/refresh: packages, mise, legacy cleanup, stow, git identity, hooks, services, T3 push, `~/.local/bin/dots` symlink |
| `dots doctor` | Read-only health check: symlinks, commands, login shell, mise tools, packages, git identity, T3 drift, secrets contexts |
| `dots t3 pull` | Copy live T3 Code settings into `t3/` |
| `dots t3 push` | Apply `t3/` settings to the live T3 Code install |
| `dots t3 diff` | Diff live vs tracked T3 settings |
| `dots secret <cmd>` | Env vars / API keys: `set`, `get`, `ls`, `rm`, `sync`, `import`, `ctx`, `run`, `reload`, `doctor` |
| `dots secret --ctx NAME <cmd>` | Same commands against a client context project |

After the first install, `dots` is on your `PATH` via `~/.local/bin/dots`.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on pushes and pull requests
to `master`, plus manual dispatch:

- **lint** — shellcheck, `zsh -n`/`bash -n` syntax checks, JSON validity, and
  parsing `stow/common/git/.config/git/config`.
- **secrets** — full-history `gitleaks` scan using `.gitleaks.toml`.
- **bootstrap-linux** — runs `./bootstrap` as a fresh non-root user in an
  Ubuntu 24.04 container with `MISE_DISABLE_TOOLS=erlang,elixir,ruby`, then
  runs `dots doctor`.
- **stow-macos** — simulates stowing every `common` and `darwin` package into
  a temporary `$HOME` and checks bash syntax.

## Adding a package

1. Create `stow/<group>/<pkg>/...` mirroring the target path, e.g.
   `stow/common/foo/.config/foo/config.toml`.
2. Pick the group: `common` (both OSes), `darwin` (macOS only), or `linux`
   (Linux only).
3. Run `dots install` (it stows every package in `common` + the current OS), or
   stow just the new one:

   ```bash
   stow --no-folding -d stow/common -t ~ foo
   ```

## Adding a CLI tool

Add it to `stow/common/mise/.config/mise/config.toml`, then lock and install:

```bash
mise lock -g -p linux-x64,macos-arm64   # lock for both machines
mise install
```

Commit `config.toml` and `mise.lock` together. Anything that is not
available through mise (GUI apps, system daemons) belongs in `packages/Brewfile`
or `packages/apt.txt` instead.

## Supply-chain cooldown

New dependency versions are ignored for 7 days:

- **npm** — `dots install` ensures `~/.npmrc` has `min-release-age=7`. The file
  also holds a private auth token and machine-specific prefix, so it is never
  tracked.
- **pnpm** — the tracked `stow/common/pnpm/.config/pnpm/rc` sets
  `minimumReleaseAge=10080` (minutes).
- **uv/pip** — `UV_EXCLUDE_NEWER` and the `sfw` wrappers in `common.zsh`.

## T3 Code settings

T3 Code rewrites `settings.json` and `keybindings.json` atomically under
`${T3CODE_HOME:-$HOME/.t3}/userdata`, so they are **never** stowed — they are
copied.

- Change settings in the app → `dots t3 pull` → commit `t3/`.
- On the other machine → `dots t3 push` → restart/reload T3 Code.

`t3/settings.base.json` is a portable subset: project overrides, auto-pull
overrides, and source-control hosts (tokens) are stripped on pull. Push
deep-merges the live file with the base, with `t3/` winning.

## Secrets

Env vars and API keys live in a self-hosted Infisical instance and are
mirrored onto each machine by `dots secret`. Personal secrets use the
`dot-env` project (folders below); each client gets its own project (see
[Client contexts](#client-contexts)). `~/.env` still holds machine-local
bootstrap values (git identity, etc.); project secrets belong in Infisical,
never in a stowed file.

Each machine authenticates with a universal-auth identity stored in
`~/.config/dot/infisical.env` (mode 600, never committed):

```
INFISICAL_DOMAIN=https://infisical.akshaydeshraj.me
INFISICAL_PROJECT_ID=<uuid>
INFISICAL_ENV=prod
DOT_MACHINE=vps            # or macbook
INFISICAL_UA_CLIENT_ID=...
INFISICAL_UA_CLIENT_SECRET=...
```

`DOT_MACHINE` selects the machine folder and keeps peer sync from syncing
itself.

### Folders and precedence

| Folder | Who uses it |
|---|---|
| `/shared` | both machines |
| `/agents` | keys coding agents use (may later move behind Infisical Agent Vault) |
| `/mac` | macbook only |
| `/vps` | vps only |

Resolution precedence is **machine folder > `/agents` > `/shared`**, so the
same name can be overridden per machine or per purpose.

### Commands

| Command | What it does |
|---|---|
| `dots secret set NAME` | Upsert a secret, then sync this machine and the peer |
| `dots secret get NAME` | Print exactly one value (or `--copy`) |
| `dots secret ls` | List names and folders, never values |
| `dots secret rm NAME (--scope S \| --ctx NAME)` | Delete from one folder or client context, then sync |
| `dots secret sync` | Refresh personal files and every context cache from Infisical |
| `dots secret import FILE` | Import dotenv lines into a folder |
| `dots secret ctx [DIR]` | Print the client context for a directory (or `personal`) |
| `dots secret run -- CMD` | Run a command with the detected (or `--ctx`) context secrets |
| `dots secret reload` | Make shells / T3 Code pick up new values |
| `dots secret doctor` | Check creds, access, contexts, files and the sync job |

Values are never taken from argv. `set` reads them with a hidden prompt, from
the macOS clipboard (`--clip`), from a file (`--from-file`), or from stdin
(`--stdin`). `NAME` must match `^[A-Z_][A-Z0-9_]*$`; the default scope is
`shared`.

```bash
dots secret set OPENAI_API_KEY --scope agents       # hidden prompt
dots secret set GH_TOKEN --clip                     # macOS clipboard
dots secret set SENTRY_AUTH_TOKEN --from-file ~/Downloads/token
printf '%s' "$KEY" | dots secret set LLM_API_KEY --stdin

dots secret get OPENAI_API_KEY                      # prints one value
dots secret get OPENAI_API_KEY --copy               # pbcopy / OSC 52

dots secret ls
dots secret import .env.local --scope agents
dots secret rm OLD_KEY --scope shared
dots secret sync
dots secret reload
dots secret doctor

# Client context (project at /; --scope cannot be combined with --ctx)
dots secret --ctx shovel set CLIENT_API_KEY --stdin
dots secret --ctx shovel get CLIENT_API_KEY
dots secret --ctx shovel ls
dots secret ctx ~/code/shovel-monorepo
dots secret run -- npm test
```

`set`, `rm` and `import` also sync the other machine over
`ssh` (`config/hosts`); `--no-peer` skips that. A failed peer sync is only a
warning — the peer catches up on its next scheduled sync. `--reload` runs
`dots secret reload` afterwards.

### Where values land

- `~/.config/dot/secrets.zsh` — `export NAME='value'` lines, sourced by
  `~/.zshrc` right after `~/.env`. New shells and agent tool commands see
  these immediately.
- `~/.config/dot/secrets.env` — systemd `EnvironmentFile` format, loaded by
  `t3code.service` through the `50-dots-secrets.conf` drop-in. Restart the unit
  to apply.
- `~/.config/dot/secrets.names` — the personal secret names, used to unset
  personal variables inside `strict` client contexts.
- `~/.config/dot/ctx/<name>.zsh` and `ctx/<name>.names` — one cache per client
  context. Client values never enter `secrets.zsh` or `secrets.env`.
- macOS: T3 Code reads the login shell environment, so it picks up new values
  after the app is restarted (`dots secret reload --force`).
- These files are mode 600 and written atomically. `~/.config/dot/secrets.synced`
  records the timestamp and count of the last personal sync.

`dots secret sync` runs after `dots install`, on demand, and in the background
every 15 minutes (systemd `dots-secret-sync.timer` on Linux, a launchd agent on
macOS). If Infisical is unreachable the previous files are kept, so shells and
T3 keep working; on a machine that has never synced, `sync` exits 1.

### Client contexts

Client keys must never mix with personal keys. Each client owns a separate
Infisical project, with secrets at path `/` in env `prod` and no folders. The
machine identities (`dot-macbook`, `dot-vps`) are members of those projects.

`config/contexts` maps a repo's git origin to a context:

```
# name   infisical-project-id                   mode    git remote patterns
shovel   05f7ffd8-7780-4718-a48a-ebbe1a85fc6a   strict  *github.com[:/]shovelers/*
skit     0487e2ec-049a-42f8-9706-ce853f4ed478   strict  *gitlab.com[:/]skit-ai/* *github.com[:/]skit-ai/*
```

- `strict` — inside the context, every personal name is unset before the
  client values are applied.
- `merge` — personal names stay; context values override on collision.

`--ctx NAME` targets a client project for `set`, `get`, `ls`, `rm` and
`import`. It may appear before or after the subcommand, and cannot be combined
with `--scope`.

```bash
dots secret --ctx shovel set CLIENT_API_KEY --stdin
dots secret --ctx shovel get CLIENT_API_KEY
dots secret --ctx shovel ls
dots secret --ctx shovel import .env.client
dots secret --ctx shovel rm OLD_CLIENT_KEY
```

`dots secret ctx DIR` resolves `git -C DIR rev-parse --show-toplevel`, reads
`remote.origin.url` there and prints the matching context, or `personal`.
Matches are checked in `config/contexts` order.

`dots secret run [--ctx NAME] -- CMD…` detects the context from `$PWD`, builds
the environment (strict contexts unset `secrets.names`), sources
`ctx/<name>.zsh`, exports `DOT_CTX`, and execs `CMD`. If the cache is missing
it runs `dots secret sync --quiet` first. `personal` just execs.

The zsh hook in `~/.config/zsh/contexts.zsh` does the same on every `chpwd`
(pure zsh + git, cached per repo): it unsets the old context's names, restores
personal secrets after a strict context, applies the new context, and sets
`DOT_CTX`. Starship shows `⎔ <context>` while a client context is active.
This runs in agent shells too, so agents inherit the right client keys.

`dots secret sync` refreshes every context cache. A failing client project
warns and keeps that context's previous files, so one broken client does not
affect personal secrets or the other clients. `dots secret doctor` reports
each context's reachability and cache age.

To add a client:

1. Create an Infisical project and add its secrets at `/` in `prod`.
2. Give the `dot-macbook` and `dot-vps` identities member access.
3. Add a line to `config/contexts` with the project ID, mode and origin glob.
4. Run `dots secret sync` (or `dots install` on both machines).

### T3 agent flow

When an agent needs a key, it asks for it through T3's secret card with file
delivery. The value arrives as a file, and the agent runs:

```bash
dots secret set NAME --from-file /path/to/delivered-file --scope agents
```

The value never enters the agent's command line or transcript; it is stored in
Infisical and delivered to this machine by the next sync.

### Security trade-off

Any process that can read the environment can read the values: an agent
running in a shell that sourced `secrets.zsh` can print `/agents` values. That
is the cost of file/environment delivery. **Infisical Agent Vault** (credential
proxy) is the planned next layer for `/agents`: the agent gets a brokered
credential for one specific target instead of the raw value.

### Re-provisioning a machine identity

Create a universal-auth identity in Infisical with read access to `dot-env`
and every client project, then write the file above (mode 600) with the new
`clientId` / `clientSecret` and the matching `DOT_MACHINE`. Run
`dots secret sync` (or `dots install`) and `dots secret doctor`. To rotate the
identity, replace the two `INFISICAL_UA_*` values, delete
`~/.config/dot/.token`, and grant the new identity member access to the client
projects.

## Agent shells

Claude Code, Codex, OpenCode and T3 Code snapshot `~/.zshrc` for their own
shells. When `CLAUDECODE`, `T3CODE_THREAD_ID`, `CODEX_SANDBOX`, `CODEX_THREAD_ID`
or `OPENCODE` is set, `~/.zshrc` exports `DOT_AGENT_SHELL=1` and skips the
tool-replacement aliases (`grep→rg`, `cat→bat`, `ls→eza`, …) and the Infisical
agent wrappers. Agents get plain tools and the real CLIs.

Machine-local, untracked shell config goes in `~/.config/zsh/local.zsh`.

Git identity is **not** in the repo. `dots install` writes
`~/.config/git/identity` from `GIT_USER_NAME` / `GIT_USER_EMAIL`, which
`~/.config/git/config` includes. `GIT_USER_NAME` must be a full name
(e.g. `Ada Lovelace`), never an email address. Identity is global only;
`dots install` removes any repo-local `user.name`/`user.email` override.

## Remote hosts

Remote hosts use Tailscale MagicDNS names (no IPs in `~/.env`):

- `vps` — mosh to `ubuntu@terminator-silver` (the OVH VPS) and attach to tmux.
- `nas` — SSH to `akshaydeshraj@nas`.

## Theme

**Tokyo Night Storm**, defined in
[`themes/tokyo-night-storm/palette.sh`](themes/tokyo-night-storm/palette.sh)
(the source of truth). App-side hex values are propagated manually where the app
cannot import shell variables — see
[`themes/tokyo-night-storm/THEME.md`](themes/tokyo-night-storm/THEME.md).
Wallpapers are generated from the palette with `wallpapers/generate.sh`.

## AeroSpace (macOS)

Six workspaces. Zen opens on 1, T3 Code on 2, Bitwarden on 3; 4–6 are free.
`alt-1..6` switches, `alt-shift-1..6` moves the window, `alt-h/j/k/l` focuses,
`alt-shift-h/j/k/l` moves, `alt-f` fullscreen, `alt-tab` previous workspace.
The full key list is at the top of `stow/darwin/wm/.config/aerospace/aerospace.toml`.
`scripts/macos-defaults.sh` turns off the macOS features that fight a tiling
window manager (Stage Manager, edge tiling, click-wallpaper-to-show-desktop,
per-display Spaces) and groups windows by app in Mission Control.

## tmux keybinds

- `Alt+K` — fzf session switcher (popup)
- `Alt+J` — switch to last session
- `prefix + e` — toggle yazi file explorer
- `prefix + g` — lazygit popup

## Manual steps

After `dots install`:

- **macOS**: grant Accessibility permission to AeroSpace; log out and back in
  for the full set of `defaults` changes; keep one native Space per display.
- **Both**: sign in to T3 Code, then log in to the agent CLIs you use
  (`claude`, `codex`, `opencode`); run `gh auth login` if not already
  authenticated.
