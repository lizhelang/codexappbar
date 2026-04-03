# Codexbar Repository Guidance

This repository ships two operator surfaces:

- the macOS menu bar app
- the bundled CLI `codexbarctl`

For any task that adds, imports, or activates an OpenAI OAuth account, prefer the CLI over the GUI.

## Preferred OAuth workflow

1. Human-driven terminal flow:
   - `codexbarctl openai login`
2. Automation / AI flow:
   - `codexbarctl openai login start`
   - `codexbarctl openai login complete --flow-id <id> --callback-url <url>`
   - or `--code <code>`
3. Account switching:
   - `codexbarctl accounts list`
   - `codexbarctl accounts activate --account-id <id>`

## Binary resolution

Use this order when invoking the CLI:

1. `codexbarctl` from `PATH`
2. `/Applications/codexbar.app/Contents/MacOS/codexbarctl`
3. A locally built product from this repo after running:
   - `xcodebuild -scheme codexbarctl -destination 'platform=macOS' build`

## Safety rules

- Do not manually edit `~/.codex/auth.json` or `~/.codex/config.toml` when `codexbarctl` can perform the operation.
- Do not print `access_token`, `refresh_token`, or `id_token` in logs, output, or summaries.
- If the CLI is unavailable and low-level repair is explicitly required, mention that the normal path is `codexbarctl` before editing auth/config files directly.
