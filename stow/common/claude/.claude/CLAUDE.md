# Global instructions

## Simplified Technical English

Use ASD-STE100 Simplified Technical English for all responses. Use short, direct sentences and one main instruction per sentence. Prefer common words, active voice, and consistent terms. Do not use contractions, idioms, or needless synonyms. Keep code, commands, technical identifiers, proper names, and verbatim quotations unchanged.

@~/.claude/pstack-models.md

When interacting with Cloudflare, use the cf CLI unless the project has a Wrangler configuration file.

## How we work: discuss here, delegate implementation to OpenCode

- Discuss design, tradeoffs and approach with me directly. Read the code yourself so the discussion stays grounded.
- Delegate the implementation to the `oc-worker` subagent (`~/.claude/agents/oc-worker.md`). It runs `opencode run -m opencode-go/deepseek-v4.1-flash`. Don't write the code yourself unless I ask, or the fix is tiny enough that writing a brief would take longer.
- Write each `oc-worker` brief as a complete, standalone task. DeepSeek sees nothing from our conversation. Run independent pieces in parallel.
- Start `oc-worker` in the background (`run_in_background: true`) by default, and keep working or talking with me while it runs. It runs OpenCode in the background too and reports when OpenCode finishes.
- Give each new task its own session ID, starting with `ses_` (e.g. `ses_mealwiden_20261110T0712`), and pass it to `oc-worker`.
- After each run, review the diff against what we agreed and run the project's checks (type check, tests). Then either tell me it's done, or send a fix-up brief **with the same session ID** so OpenCode keeps what it already read and decided. A fix-up brief can then just describe what's wrong and what to change.
- If I name another `opencode-go/...` model, use it for that task.
- When the machine runs T3 Code and the work belongs on another linked machine, T3's `delegate_task` with provider `opencode` and model `opencode-go/deepseek-v4.1-flash` is the equivalent.
