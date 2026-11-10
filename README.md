# dotfiles

Personal dev environment for two machines:

- **macOS laptop** (Apple Silicon, Homebrew at `/opt/homebrew`) — AeroSpace,
  SketchyBar, Ghostty, Zed, tmux, zsh.
- **Ubuntu 24.04 VPS** (x86_64, no Homebrew) — tmux, zsh, CLI tooling, systemd.

Configs are symlinked into `$HOME` with [GNU Stow](https://www.gnu.org/software/stow/).
CLI tools and runtimes are installed with [mise](https://mise.jdx.dev/).

## Quick start

```bash
git clone https://github.com/akshaydeshraj/dotfiles ~/Code/personal/dotfiles
cd ~/Code/personal/dotfiles
cp .env.example ~/.env && $EDITOR ~/.env   # fill in real values
./bootstrap
```

`bootstrap` installs the minimum needed to run the CLI (Xcode CLT + Homebrew +
`stow jq` on macOS; `stow jq git curl` via apt on Linux), then hands off to
`dot install`.

## Layout

```
bin/dot                 # cross-platform CLI (install / doctor / t3 / secret)
bin/dot-secret          # env var + API key manager (Infisical)
bootstrap               # first-run entry point
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

## `dot` commands

| Command | What it does |
|---|---|
| `dot install` | Idempotent bootstrap/refresh: packages, mise, legacy cleanup, stow, git identity, hooks, services, T3 push, `~/.local/bin/dot` symlink |
| `dot doctor` | Read-only health check: symlinks, commands, login shell, mise tools, packages, git identity, T3 drift |
| `dot t3 pull` | Copy live T3 Code settings into `t3/` |
| `dot t3 push` | Apply `t3/` settings to the live T3 Code install |
| `dot t3 diff` | Diff live vs tracked T3 settings |
| `dot secret <cmd>` | Env vars / API keys: `set`, `get`, `ls`, `rm`, `sync`, `import`, `reload`, `doctor` |

After the first install, `dot` is on your `PATH` via `~/.local/bin/dot`.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on pushes and pull requests
to `master`, plus manual dispatch:

- **lint** — shellcheck, `zsh -n`/`bash -n` syntax checks, JSON validity, and
  parsing `stow/common/git/.config/git/config`.
- **secrets** — full-history `gitleaks` scan using `.gitleaks.toml`.
- **bootstrap-linux** — runs `./bootstrap` as a fresh non-root user in an
  Ubuntu 24.04 container with `MISE_DISABLE_TOOLS=erlang,elixir,ruby`, then
  runs `dot doctor`.
- **stow-macos** — simulates stowing every `common` and `darwin` package into
  a temporary `$HOME` and checks bash syntax.

## Adding a package

1. Create `stow/<group>/<pkg>/...` mirroring the target path, e.g.
   `stow/common/foo/.config/foo/config.toml`.
2. Pick the group: `common` (both OSes), `darwin` (macOS only), or `linux`
   (Linux only).
3. Run `dot install` (it stows every package in `common` + the current OS), or
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

- **npm** — `dot install` ensures `~/.npmrc` has `min-release-age=7`. The file
  also holds a private auth token and machine-specific prefix, so it is never
  tracked.
- **pnpm** — the tracked `stow/common/pnpm/.config/pnpm/rc` sets
  `minimumReleaseAge=10080` (minutes).
- **uv/pip** — `UV_EXCLUDE_NEWER` and the `sfw` wrappers in `common.zsh`.

## T3 Code settings

T3 Code rewrites `settings.json` and `keybindings.json` atomically under
`${T3CODE_HOME:-$HOME/.t3}/userdata`, so they are **never** stowed — they are
copied.

- Change settings in the app → `dot t3 pull` → commit `t3/`.
- On the other machine → `dot t3 push` → restart/reload T3 Code.

`t3/settings.base.json` is a portable subset: project overrides, auto-pull
overrides, and source-control hosts (tokens) are stripped on pull. Push
deep-merges the live file with the base, with `t3/` winning.

## Secrets

Env vars and API keys live in one self-hosted Infisical project, `dot-env`,
and are mirrored onto each machine by `dot secret`. `~/.env` still holds
machine-local bootstrap values (git identity, etc.); project secrets belong
in Infisical, never in a stowed file.

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
| `dot secret set NAME` | Upsert a secret, then sync this machine and the peer |
| `dot secret get NAME` | Print exactly one value (or `--copy`) |
| `dot secret ls` | List names and folders, never values |
| `dot secret rm NAME --scope S` | Delete from one folder, then sync |
| `dot secret sync` | Refresh the local files from Infisical |
| `dot secret import FILE` | Import dotenv lines into a folder |
| `dot secret reload` | Make shells / T3 Code pick up new values |
| `dot secret doctor` | Check creds, access, files and the sync job |

Values are never taken from argv. `set` reads them with a hidden prompt, from
the macOS clipboard (`--clip`), from a file (`--from-file`), or from stdin
(`--stdin`). `NAME` must match `^[A-Z_][A-Z0-9_]*$`; the default scope is
`shared`.

```bash
dot secret set OPENAI_API_KEY --scope agents       # hidden prompt
dot secret set GH_TOKEN --clip                     # macOS clipboard
dot secret set SENTRY_AUTH_TOKEN --from-file ~/Downloads/token
printf '%s' "$KEY" | dot secret set LLM_API_KEY --stdin

dot secret get OPENAI_API_KEY                      # prints one value
dot secret get OPENAI_API_KEY --copy               # pbcopy / OSC 52

dot secret ls
dot secret import .env.local --scope agents
dot secret rm OLD_KEY --scope shared
dot secret sync
dot secret reload
dot secret doctor
```

`set`, `rm` and `import` also sync the other machine over
`ssh` (`config/hosts`); `--no-peer` skips that. A failed peer sync is only a
warning — the peer catches up on its next scheduled sync. `--reload` runs
`dot secret reload` afterwards.

### Where values land

- `~/.config/dot/secrets.zsh` — `export NAME='value'` lines, sourced by
  `~/.zshrc` right after `~/.env`. New shells and agent tool commands see
  these immediately.
- `~/.config/dot/secrets.env` — systemd `EnvironmentFile` format, loaded by
  `t3code.service` through the `50-dot-secrets.conf` drop-in. Restart the unit
  to apply.
- macOS: T3 Code reads the login shell environment, so it picks up new values
  after the app is restarted (`dot secret reload --force`).
- Both files are mode 600 and written atomically. `~/.config/dot/secrets.synced`
  records the timestamp and count of the last sync.

`dot secret sync` runs after `dot install`, on demand, and in the background
every 15 minutes (systemd `dot-secret-sync.timer` on Linux, a launchd agent on
macOS). If Infisical is unreachable the previous files are kept, so shells and
T3 keep working; on a machine that has never synced, `sync` exits 1.

### T3 agent flow

When an agent needs a key, it asks for it through T3's secret card with file
delivery. The value arrives as a file, and the agent runs:

```bash
dot secret set NAME --from-file /path/to/delivered-file --scope agents
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

Create a universal-auth identity in Infisical with read access to `dot-env`,
then write the file above (mode 600) with the new `clientId` /
`clientSecret` and the matching `DOT_MACHINE`. Run `dot secret sync` (or
`dot install`) and `dot secret doctor`. To rotate the identity, replace the
two `INFISICAL_UA_*` values and delete `~/.config/dot/.token`.

## Agent shells

Claude Code, Codex, OpenCode and T3 Code snapshot `~/.zshrc` for their own
shells. When `CLAUDECODE`, `T3CODE_THREAD_ID`, `CODEX_SANDBOX`, `CODEX_THREAD_ID`
or `OPENCODE` is set, `~/.zshrc` exports `DOT_AGENT_SHELL=1` and skips the
tool-replacement aliases (`grep→rg`, `cat→bat`, `ls→eza`, …) and the Infisical
agent wrappers. Agents get plain tools and the real CLIs.

Machine-local, untracked shell config goes in `~/.config/zsh/local.zsh`.

Git identity is **not** in the repo. `dot install` writes
`~/.config/git/identity` from `GIT_USER_NAME` / `GIT_USER_EMAIL`, which
`~/.config/git/config` includes. `GIT_USER_NAME` must be a full name
(e.g. `Ada Lovelace`), never an email address. Identity is global only;
`dot install` removes any repo-local `user.name`/`user.email` override.

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

## tmux keybinds

- `Alt+K` — fzf session switcher (popup)
- `Alt+J` — switch to last session
- `prefix + e` — toggle yazi file explorer
- `prefix + g` — lazygit popup

## Manual steps

After `dot install`:

- **macOS**: grant Accessibility permission to AeroSpace; log out and back in
  for the full set of `defaults` changes; keep one native Space per display.
- **Both**: sign in to T3 Code, then log in to the agent CLIs you use
  (`claude`, `codex`, `opencode`); run `gh auth login` if not already
  authenticated.
