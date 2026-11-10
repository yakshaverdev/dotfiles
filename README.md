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
bin/dot                 # cross-platform CLI (install / doctor / t3)
bootstrap               # first-run entry point
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
stow/darwin/<pkg>       # macOS only: ghostty wm zed
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

Secrets live in `~/.env` (chmod 600, never committed). `.env.example` lists the
required variables. Project secrets are injected by the Infisical wrappers in
`~/.config/zsh/infisical.zsh` (`claude`, `codex`, `pi`, `aws`); nothing secret
belongs in a stowed file.

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
