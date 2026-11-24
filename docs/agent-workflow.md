# Agent workflow

This page explains how coding agents run on these machines. It covers terminal Claude, terminal Codex, OpenCode and T3 Code. Run `dots doctor` to check the shared prerequisites.

## Shared sources

| What | Source | Target |
|---|---|---|
| Global skills | `packages/agent-skills` | `~/.agents/skills`, linked into each agent |
| Project skills | `.agents/skills` or `.claude/skills`, plus `skills-lock.json` | The same repo, restored on each machine |
| Global MCP | `config/agents/mcp.json` | User scope of every agent |
| Project MCP | `<repo>/.mcp.json` | Codex and OpenCode project config; Claude reads it directly |
| Client MCP | `config/agents/<context>/mcp.json` | Resolved with client secrets at sync time |
| Plugins | `packages/agent-plugins` | Codex and OpenCode plugin lists |

`dots agents sync` translates these sources into the native config of Claude Code, Codex and OpenCode. `dots install` runs the global level only. Run `dots agents sync` inside a repo for its project level. See [`config/agents/README.md`](../config/agents/README.md) for the levels, the trust rules and the secret handling.

`dots skills` installs the global skills from the manifest. `dots skills upgrade` updates skills, marketplaces and plugins.

## Terminal Claude

| Topic | How it works |
|---|---|
| Launch path | In zsh, `~/.zshenv` puts `<repo>/bin/shims` first on PATH. `bin/shims/claude` execs `~/.local/bin/claude-ctx`. That file is a link to `bin/claude-ctx`. |
| Accounts | `claude-ctx` fails over between the `team` account (primary) and the `ultra` account (fallback). It picks the first account that has a token and is not limited. If both are limited, it picks the one that resets first. |
| Tokens | `CLAUDE_TOKEN_TEAM` and `CLAUDE_TOKEN_ULTRA` come from the environment first, then `~/.config/dot/claude-tokens.env`. `dots secret sync` puts the tokens in that file and not in `secrets.zsh` or `secrets.env`. |
| Caller auth | If `ANTHROPIC_AUTH_TOKEN` or `ANTHROPIC_BASE_URL` is set, the caller manages auth. `claude-ctx` does not fail over, and it removes any subscription token and account from the environment. It also keeps `ANTHROPIC_API_KEY` in this case. Otherwise it unsets that key, so the signed-in subscription takes precedence. |
| Context | It sources `~/.config/zsh/contexts.bash`. Claude and the MCP servers it starts inherit the client context of the working directory. |
| npx guard | If the first PATH entry is an `_npx/.../node_modules/.bin` folder with a half-installed `@anthropic-ai/claude-code` package, `claude-ctx` exits 1 and prints the folder to remove. |
| Failover in a terminal | With no caller token, a TTY and no T3 thread, it runs a wrapper. On a rate limit it restarts Claude with `--resume <session> continue`, up to 3 times. |
| State | `~/.local/state/claude-accounts` (or `$XDG_STATE_HOME/claude-accounts`). It holds the limit files, rate files and `failover.log`. |
| Permissions | The interactive shell wrapper in `agents.zsh` adds `--dangerously-skip-permissions`. It adds `--chrome` on macOS and `--continue` when `.claude/conversations` exists. `skipDangerousModePermissionPrompt` is true in `stow/common/claude/.claude/settings.json`. |

## Terminal Codex

| Topic | How it works |
|---|---|
| Launch | `codex` from the standalone installer, usually `~/.local/bin/codex`. The macOS app also ships `codex` at `/Applications/Codex.app/Contents/Resources/codex`. The `dots` scripts check both paths when `codex` is not on PATH. |
| Global instructions | `~/.codex/AGENTS.md`, stowed from `stow/common/codex/.codex/AGENTS.md`. |
| Global MCP | `dots agents sync` writes `~/.codex/config.toml`. It uses the Codex CLI where it can and writes TOML for the rest. |
| Project MCP | `dots agents sync` writes `<repo>/.codex/config.toml` when the project has servers, and adds `[projects."<path>"]` with `trust_level = "trusted"` to `~/.codex/config.toml` when no entry exists. |
| Plugins | Installed from `packages/agent-plugins` with `codex plugin marketplace add` and `codex plugin add`. Run `/hooks` once in an interactive session to trust the pstack hook. |
| Permissions | The interactive shell wrapper in `agents.zsh` adds `--dangerously-bypass-approvals-and-sandbox`. The repo sets no Codex approval policy. |

## OpenCode

| Topic | How it works |
|---|---|
| Launch | mise installs `opencode`. The binary is `~/.local/share/mise/shims/opencode`. |
| Updates | `dots install` sets `"autoupdate": false` in `~/.config/opencode/opencode.json`, because mise owns the binary. Upgrade with `dots upgrade opencode`. |
| Global MCP | `dots agents sync` writes `~/.config/opencode/opencode.json`. `${VAR}` becomes `{env:VAR}`. |
| Project MCP | `dots agents sync` writes `<repo>/opencode.json` when the project has servers, and adds it to `.git/info/exclude`. |
| Plugins | Installed from `packages/agent-plugins` with `opencode plugin add`. Restart the OpenCode service to load a new plugin. |
| Delegation | `opencode run -m <model> -s <session-id> --archived "<task>"` runs a task. The `oc-worker` agent uses this command. |
| Permissions | The repo defines no OpenCode permission or approval setting, and no shell wrapper for it. OpenCode uses its own defaults. |

## T3 Code

| Topic | How it works |
|---|---|
| Providers | The tracked settings name three provider instances: `claudeAgent` runs `~/.local/bin/claude-ctx`; `opencode` runs the mise shim; `grok` runs a binary named `grok`. |
| Claude in T3 | T3 starts Claude through `claude-ctx`. In T3, `claude-ctx` does not use the terminal wrapper. The `StopFailure` hook runs `claude-ctx __limit`; a rate limit ends the Claude process, and T3 reopens the thread on the other account. |
| Worktree script | A project script named `Agents sync` runs `"$HOME/.local/bin/dots" agents sync --project-only` when T3 creates a worktree. T3 stores project scripts in its user data, not in `t3/`. |
| Settings | `dots t3 pull`, `dots t3 push` and `dots t3 diff` move keybindings and base settings. Project overrides and source control hosts are not tracked. See [`docs/recovery.md`](recovery.md). |
| Secrets | On Linux, `t3code.service` loads `~/.config/dot/secrets.env` and sets `BASH_ENV=~/.config/zsh/contexts.bash`. On macOS, T3 reads the login shell environment, so restart the app after a sync. |
| Permissions | `claude-ctx` adds no permission flag. The permission mode comes from the arguments that T3 passes. |

## Delegation to `oc-worker`

The global `~/.claude/CLAUDE.md` holds the working rules:

- Discuss design and tradeoffs in the main session. Implement through the `oc-worker` subagent (`~/.claude/agents/oc-worker.md`).
- `oc-worker` runs `opencode run -m opencode-go/deepseek-v4.1-flash`. Name another `opencode-go/...` model to use it for that task.
- Write a complete, standalone brief. OpenCode does not see the parent conversation.
- Give each task a session ID that starts with `ses_`. Reuse the same ID for a fix-up, so OpenCode keeps its earlier context.
- Start `oc-worker` in the background. Review the diff and run the project checks after it finishes.
- pstack work is the exception. pstack picks its own models from `pstack-models.md`.
- On another linked machine, T3's `delegate_task` with provider `opencode` and model `opencode-go/deepseek-v4.1-flash` is the equivalent.

## pstack

pstack is installed as a Claude plugin (`pstack@pstack-claude`), a Codex plugin and an OpenCode plugin.

Each agent gets a `pstack-models.md` sheet:

- Claude: `~/.claude/pstack-models.md` (stowed from `stow/common/claude/.claude/`).
- Codex: `~/.codex/pstack-models.md`.
- OpenCode: `~/.config/opencode/pstack-models.md`.

All three sheets contain `session hook: off`. The sheet documentation says this stops the Claude Code or Codex `SessionStart` hook that injects the poteto-mode mandate. The Claude sheet also sets the model for each pstack role.

## Secret scope

Personal secrets come from `/shared`, `/agents` and this machine's folder (`/mac` or `/vps`). Precedence is machine folder, then `/agents`, then `/shared`.

A client context is a separate Infisical project, or a list of projects. `config/contexts` maps a git origin pattern to a context and a mode:

- `strict` — every personal name is unset before the client values are applied.
- `merge` — personal names stay, and client values win on a collision.

`DOT_CTX` names the active client context. `dots secret ctx DIR` prints the context for a directory, or `personal`.

Use a context for one command:

```bash
dots secret run --ctx NAME -- CMD
```

Without `--ctx`, `dots secret run` detects the context from `$PWD`. If the context cache is missing, it runs `dots secret sync --quiet` first.

The zsh `chpwd` hook in `contexts.zsh` applies the same rules in an interactive shell. Agent command shells get the context from `~/.zshenv` (zsh) or from `BASH_ENV` (bash), because they do not read `~/.zshrc`. Client values are cached in `~/.config/dot/ctx/<name>.zsh`.

`dots secret --ctx NAME set|get|ls|rm|import` targets a client project. `--ctx` cannot be combined with `--scope`. Client MCP references are resolved at sync time and written to mode-600 files. Global and project MCP references stay as references.

## Permission summary

| Entry point | Default |
|---|---|
| Interactive terminal `claude` | `--dangerously-skip-permissions` from `agents.zsh`, and `skipDangerousModePermissionPrompt` in `settings.json` |
| Interactive terminal `codex` | `--dangerously-bypass-approvals-and-sandbox` from `agents.zsh` |
| Agent-owned shells (`CLAUDECODE`, `T3CODE_THREAD_ID`, `CODEX_THREAD_ID`, `CODEX_SANDBOX`, `OPENCODE`) | `~/.zshrc` sets `DOT_AGENT_SHELL=1` and does not source `agents.zsh`, so the wrappers do not apply |
| T3 Code | `claude-ctx` adds no flag; T3 passes its own arguments |
| OpenCode | No wrapper and no permission setting in this repo |

`stow/common/claude/.claude/settings.json` has no `permissions` block. Its only permission-related key is `skipDangerousModePermissionPrompt`.
