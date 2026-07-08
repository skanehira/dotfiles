# Codex Global Guidance

## Working Style

- Respond in Japanese unless the user explicitly asks for another language.
- Keep answers concise and concrete.
- Read the relevant files before changing code, and follow the repository's existing patterns.
- Prefer `rg` / `rg --files` for repository search.
- Do not expose, commit, or summarize secrets from auth files, tokens, caches, logs, or histories.

## Codex Product Facts

- For Codex/OpenAI product behavior, verify against official OpenAI documentation when accuracy matters.
- Keep `~/.codex/auth.json`, sqlite state, logs, history, caches, and `[projects.*]` trust state local to the machine.
