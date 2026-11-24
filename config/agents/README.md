# Agent MCP servers

`dots agents sync` reads one `.mcp.json` shape and writes the native config of
Claude Code, Codex and OpenCode. There are three levels:

1. **Global** — `config/agents/mcp.json` in this repo. Applies to every repo
   through the agents' user scope. `${VAR}` stays a reference because personal
   secrets are already in the agent environment.
2. **Project** — `<repo>/.mcp.json`, committed by the repo owner. Claude reads
   it natively; Codex and OpenCode get it through `dots agents sync` inside the
   repo. Project skills live in `.agents/skills` or `.claude/skills`, and
   `skills-lock.json` restores them.
3. **Client** — `config/agents/<context>/mcp.json`, where `<context>` is a name
   from `config/contexts`. It applies to repos whose origin matches that
   context. Client secrets are not in the agent environment, so every `${VAR}`
   is resolved at sync time and written as a literal value in a mode-600 file.

The global and project levels keep `${VAR}` (OpenCode gets `{env:VAR}`, Codex
gets its native `bearer_token_env_var` / `env_http_headers` / `env_vars`
fields). A reference that cannot be expressed natively, or a client reference
whose value is empty, fails that one server and the rest of the sync continues.

Both agents require a one-time trust before they read a project's config:
Claude Code needs the project trusted in `~/.claude.json` before it honours
`.claude/settings.local.json`, and Codex needs
`[projects."<repo>"] trust_level = "trusted"` in `~/.codex/config.toml`.
`dots agents sync` warns about both and never adds a trust entry.
