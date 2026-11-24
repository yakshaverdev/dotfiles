# Recovery

This guide covers common failures. Run the commands from the repository root unless a step says otherwise. Never print secret values in a terminal or a log.

## A failed `dots install`

`dots install` records failures in a list and continues with the next step. At the end it prints a `Failures:` list, a `Manual steps remaining:` list, and the backup folder when it moved files. It exits 1 when the `Failures:` list is not empty. It also exits 1 early when `~/.env` is missing. A command that is not guarded stops the run with its own error.

### What install changes

| Area | Change |
|---|---|
| Packages | `brew bundle` on macOS; `apt-get install` from `packages/apt.txt` on Linux |
| mise | Installs mise when missing, then runs `mise install` |
| Legacy cleanup | Removes dangling symlinks whose target contains `dotfiles`, under `$HOME`, `$HOME/.config`, `$HOME/.claude` and `$HOME/Applications`. On macOS it also removes the old `com.dotfiles.autosync` and `com.dotfiles.diffcheck` launchd files, and a legacy `~/Applications/Arc.app` link. |
| Stow | Links every package in `stow/common` and `stow/<os>` into `$HOME` |
| Commands | Links `bin/dots` and `bin/claude-ctx` into `~/.local/bin` |
| Supply chain | Adds `min-release-age=7` to `~/.npmrc`; sets `"autoupdate": false` in `~/.config/opencode/opencode.json` |
| Git | Writes `~/.config/git/identity`; moves a real `~/.gitconfig` to the backup folder; removes `user.name` and `user.email` from the repository's local git config; sets `core.hooksPath` to the repo `hooks/` directory |
| Secrets | Runs `dots secret sync` when `~/.config/dot/infisical.env` exists |
| Services | Enables `dots-secret-sync.timer` (Linux) or loads `com.dots.secret-sync` (macOS) when `~/.config/dot/infisical.env` exists |
| Agents | Runs `dots skills sync` and `dots agents sync --global-only` |
| T3 Code | Runs `dots t3 push` when `~/.t3/userdata` exists |
| Login shell | Changes the login shell to zsh |

On macOS, install also runs `scripts/macos-defaults.sh`, links the Zen profile when `~/Library/Application Support/zen` exists, opens AeroSpace, and starts the `sketchybar` and `borders` brew services.

### The backup folder

Install moves conflicting real files and directories to:

```
~/.dotfiles-backup/<YYYYmmdd-HHMMSS>/<path relative to $HOME>
```

The timestamp is the start time of that install run. Example: `~/.dotfiles-backup/20260101-120000/.gitconfig`.

Install backs up two kinds of files: stow conflict targets and a real `~/.gitconfig`. The legacy cleanup deletes stale symlinks and does not back them up.

`dots t3 push` makes its own backup, described in [T3 Code settings](#t3-code-settings).

### See what failed

1. Read the `Failures:` block at the end of the output. Each item names the step, for example `stow common/zsh` or `brew bundle`.
2. Read the `Manual steps remaining:` block. These items need a person, for example `gh auth login` or `sudo chsh`.
3. Run `dots doctor`. It checks links, commands, the login shell, mise tools, packages, git identity, T3 settings and secrets.

### Re-run install

1. Fix the cause of each failure.
2. Run `dots install` again.

Install is safe to repeat. A new run uses a new backup folder and does not touch the old folders.

If `~/.env` is missing, run:

```bash
cp .env.example ~/.env
$EDITOR ~/.env
```

Then run `dots install` again.

### Restore a backed-up file

Example for `~/.zshrc`:

```bash
rm -f ~/.zshrc
cp ~/.dotfiles-backup/20260101-120000/.zshrc ~/.zshrc
```

`rm -f` on a symlink removes only the link. Use `cp`, not `mv`, so the backup stays in place.

The path is now a real file again. A later `dots install` moves it to a new backup folder and links the repository file. `dots doctor` reports a real file where it expects a symlink.

## A bad mise upgrade

`dots upgrade <tool>` runs:

```bash
mise lock -g -p linux-x64,macos-arm64 --bump <tool>
mise install <tool>
```

The command updates `stow/common/mise/.config/mise/mise.lock` for Linux x64 and macOS arm64. It prints the two files to commit: `config.toml` and `mise.lock`. The lockfile pins the version for both platforms. `locked = true` makes `mise install` read the lockfile and never rewrite it.

### Return to the previous version

1. Find the upgrade commit:

   ```bash
   git log --oneline -- stow/common/mise/.config/mise/mise.lock
   ```

2. Restore the old files. Use one of these:

   ```bash
   git revert <commit>
   ```

   ```bash
   git checkout <good-commit> -- stow/common/mise/.config/mise/config.toml \
     stow/common/mise/.config/mise/mise.lock
   ```

   To discard an upgrade that you have not committed, run:

   ```bash
   git checkout -- stow/common/mise/.config/mise/config.toml \
     stow/common/mise/.config/mise/mise.lock
   ```

   To pin an older version manually, copy the previous version and its lock entry back into `config.toml` and `mise.lock`.

3. Install the pinned version:

   ```bash
   mise install <tool>
   ```

4. Check the installed version:

   ```bash
   mise ls <tool>
   ```

Revert `mise.lock` together with `config.toml`. Most tools use the version `latest` in `config.toml`; the lockfile holds the real version.

Commit and push the restored files. Then run `dots install` on the other machine.

## A broken shell startup

### Start a clean shell

```bash
zsh -f
```

`zsh -f` does not read `~/.zshenv`, `~/.zprofile`, `~/.zshrc` or the files under `~/.config/zsh`.

For bash:

```bash
bash --norc
```

`bash --norc` does not read `~/.bashrc`.

### Files to check

Check these files in this order:

1. `~/.zshenv` — read by every zsh, including non-interactive shells. It sets PATH, sets `DOTS_SHIM_DIR`, sources `~/.config/dot/secrets.zsh`, and sources `contexts.zsh` for agent shells.
2. `~/.zprofile` — Homebrew setup on macOS.
3. `~/.zshrc` — sources `~/.env`, `~/.config/dot/secrets.zsh`, `~/.config/zsh/contexts.zsh`, `common.zsh`, the OS file, `agents.zsh`, `hosts/<host>.zsh`, `local.zsh` and `plugins.zsh`.
4. `~/.config/zsh/common.zsh`, `agents.zsh`, `contexts.zsh` and `plugins.zsh`.
5. `~/.config/dot/secrets.zsh` and `~/.config/dot/ctx/<name>.zsh`.
6. `~/.env`.

Check the syntax of a file:

```bash
zsh -n ~/.zshrc
for f in ~/.config/zsh/*.zsh; do zsh -n "$f"; done
```

Find the failing file in a clean shell. Set `DOTFILES` to the repository root, then source the files one at a time:

```bash
zsh -f
export DOTFILES=<repository root>
source ~/.config/zsh/common.zsh
```

### Disable the context hook

`contexts.zsh` adds `_dots_ctx_apply` to the `chpwd` hook. Stop it for the current shell:

```bash
add-zsh-hook -d chpwd _dots_ctx_apply
```

To stop it in every new interactive shell, add that line to `~/.config/zsh/local.zsh`. That file is sourced after `contexts.zsh`.

The values that the hook already applied stay in the shell. Start the shell in `$HOME` to keep the personal values.

### Secrets at startup

`~/.zshenv` and `~/.zshrc` both source `~/.config/dot/secrets.zsh`. If the file is missing or stale, run:

```bash
dots secret sync
```

A new shell then reads the new file. In the current shell, run:

```bash
source ~/.config/dot/secrets.zsh
```

## T3 Code settings

The live files are `${T3CODE_HOME:-$HOME/.t3}/userdata/keybindings.json` and `settings.json`. The tracked copies are `t3/keybindings.json` and `t3/settings.base.json`.

| Command | Action |
|---|---|
| `dots t3 diff` | Shows a unified diff between live and tracked settings. Exits 1 when they differ. Exits 0 when they match or when T3 Code is not installed. |
| `dots t3 pull` | Copies live keybindings to `t3/keybindings.json` and filtered live settings to `t3/settings.base.json`. The filter removes project overrides, auto-pull overrides, source control hosts, device hosts and provider server passwords. |
| `dots t3 push` | Backs up the live files, copies `t3/keybindings.json`, and deep-merges `t3/settings.base.json` into live settings. The tracked base overrides live values on collisions. |

### Wrong settings

- If the live app is wrong and `t3/` is correct, run `dots t3 push`, then restart or reload T3 Code.
- If `t3/` is wrong, restore it from git, then run `dots t3 push`:

  ```bash
  git checkout -- t3/
  dots t3 push
  ```

- If a `dots t3 pull` copied bad live settings into `t3/`, revert that commit or restore the files from git. Then run `dots t3 push`.

`dots t3 push` fails when `t3/keybindings.json` or `t3/settings.base.json` is missing.

### Backups from push

Push copies the live `keybindings.json` and `settings.json` to:

```
~/.dotfiles-backup/<YYYYmmdd-HHMMSS>/t3/
```

To use a backup, quit T3 Code, then copy the file back to its live path. Example:

```bash
cp ~/.dotfiles-backup/20260101-120000/t3/settings.json \
  ~/.t3/userdata/settings.json
```

## Secrets

### Check and refresh

```bash
dots secret doctor
dots secret sync
```

`dots secret doctor` checks the credentials file and its mode, the Infisical login, read access to `/shared`, `/agents`, `/mac` and `/vps`, every client context, the local files, the last sync time and the periodic job. It exits 1 when it finds a problem.

`dots secret sync` writes these files under `~/.config/dot`:

- `secrets.zsh` — exported values for shells.
- `secrets.env` — systemd `EnvironmentFile` format for T3 Code.
- `secrets.names` — the personal names. Strict client contexts unset them.
- `claude-tokens.env` — Claude subscription tokens. `bin/claude-ctx` reads this file; the shells do not.
- `secrets.synced` — the time and count of the last sync.
- `ctx/<name>.zsh` and `ctx/<name>.names` — one cache per client context.

If Infisical is unreachable, sync keeps the old files. It exits 0 when the old files exist and 1 when this machine has never synced.

### Caches

| Path | Content |
|---|---|
| `~/.config/dot/.token` | Cached Infisical token for the personal instance |
| `~/.config/dot/.token.<instance>` | Cached token for another instance |
| `~/.config/dot/ctx/<name>.zsh` | Client context values |
| `~/.config/dot/ctx/<name>.names` | Client context names |

### Clear a bad cache

Delete a bad token cache:

```bash
rm ~/.config/dot/.token
```

The next Infisical call logs in again. `dots-secret` also deletes the cache once when the API returns HTTP 401.

Delete a bad client context cache, then rebuild it:

```bash
rm ~/.config/dot/ctx/<name>.zsh ~/.config/dot/ctx/<name>.names
dots secret sync
```

A failed context sync keeps the old files for that context. One broken client does not affect personal secrets or the other clients.

### Apply new values

New shells read the new `secrets.zsh`. In the current shell, run:

```bash
source ~/.config/dot/secrets.zsh
```

For T3 Code, run:

```bash
dots secret reload
```

On Linux, reload restarts `t3code.service` unless agent scopes are running. Use `--force` to restart anyway. On macOS, `--force` quits and reopens the app.

`dots secret set`, `rm` and `import` need write access in Infisical. Read access is enough for `sync`, `get`, `ls`, `run` and `doctor`. See [Re-provisioning a machine identity](../README.md#re-provisioning-a-machine-identity).

## MCP sync

`dots agents sync` writes agent MCP config and records its work in:

```
${XDG_STATE_HOME:-$HOME/.local/state}/dots/agents-sync.json
```

The file has this shape:

```json
{
  "version": 1,
  "targets": {
    "<key>": {
      "names": ["<server>"],
      "hashes": {"<server>": "<sha256 of the translated JSON>"}
    }
  }
}
```

Keys include `claude-user`, `codex-global`, `opencode-global`, `claude-approval:<repo>`, `claude-local:<repo>`, `codex-project:<repo>` and `opencode-project:<repo>`.

### A server removed manually is not added again

For a Claude Code entry, sync skips the `claude mcp add` call when two conditions are true:

1. The translated JSON hash equals the stored hash.
2. The stored name list still contains the server.

So if you delete that server manually, sync does not add it again while the hash stays the same.

Delete its hash entry to make the next sync apply the server again:

```bash
jq 'del(.targets["claude-user"].hashes["<server>"])' \
  ~/.local/state/dots/agents-sync.json > /tmp/agents-sync.json
mv /tmp/agents-sync.json ~/.local/state/dots/agents-sync.json
```

You can also delete the whole key. The next sync then applies every server for that key:

```bash
jq 'del(.targets["claude-user"])' \
  ~/.local/state/dots/agents-sync.json > /tmp/agents-sync.json
mv /tmp/agents-sync.json ~/.local/state/dots/agents-sync.json
```

Then run:

```bash
dots agents sync
```

OpenCode and Codex write their desired servers on every sync. Their state list only finds stale names. To remove a server from them, remove it from the source file and run sync.

### Stop a server

Remove the server from its source, then run `dots agents sync`:

- Global: `config/agents/mcp.json`
- Project: `<repo>/.mcp.json`
- Client: `config/agents/<context>/mcp.json`

Sync removes names that it applied before and that are no longer in the source. A translation failure skips that one server and continues with the rest.
