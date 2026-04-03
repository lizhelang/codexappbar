---
name: chatgpt-anon-register
description: Create a pseudonymous ChatGPT account on macOS by generating a new iCloud Hide My Email alias, reading the OpenAI verification code from Mail.app, and driving the browser signup flow without using the user's real identity.
---

# ChatGPT Anonymous Registration

Use this skill when the task is specifically:

- create a new ChatGPT account with a fresh iCloud Hide My Email alias
- keep the flow pseudonymous instead of using the user's real name or birthday
- run on macOS with `System Settings`, `Mail.app`, `cliclick`, and `playwright-cli`

Do not use this skill for:

- paid upgrades, purchases, or billing setup
- flows that require phone verification, ID checks, or other stronger identity binding
- non-macOS environments

## Preconditions

- Signed in to iCloud on the local Mac
- `隐藏邮件地址` / Hide My Email is available under iCloud+
- `Mail.app` is configured and can receive the forwarded relay mail
- Accessibility automation is enabled for `System Events`
- `cliclick`, `swift`, `osascript`, `screencapture`, and `playwright-cli` are installed
- Browser locale is compatible with the selectors used by the Playwright script

## Guardrails

- Never use the user's real name, real birthday, or any assistant identity
- Only use synthetic profile data when the user explicitly wants a pseudonymous account
- Only read recent OpenAI / ChatGPT verification mail; avoid broad mailbox scraping
- Stop and report if the site requests phone verification, payment, government ID, CAPTCHA solving by hand, or a materially different flow

## Workflow

1. Generate a new Hide My Email alias:

```bash
./register/chatgpt-anon-register/scripts/create_hide_my_email.sh
```

Optional label override:

```bash
HIDE_MY_EMAIL_LABEL="codex" ./register/chatgpt-anon-register/scripts/create_hide_my_email.sh
```

2. Register the ChatGPT account with that alias:

```bash
RELAY_EMAIL="fresh_alias@icloud.com" \
./register/chatgpt-anon-register/scripts/register_chatgpt.sh
```

Optional synthetic profile overrides:

```bash
RELAY_EMAIL="fresh_alias@icloud.com" \
ACCOUNT_NAME="River Vale" \
BIRTH_YEAR="1990" \
BIRTH_MONTH="01" \
BIRTH_DAY="08" \
./register/chatgpt-anon-register/scripts/register_chatgpt.sh
```

3. The registration script will:

- open `chat.com` and follow the `chatgpt.com` signup path
- generate a strong password if one is not provided
- pull the newest OpenAI verification code from `Mail.app`
- stop once the account reaches the post-signup onboarding state

4. To import the new account into local Codexbar without switching the current active account:

```bash
./register/scripts/create_and_import_openai_account.sh
```

## Scripts

- `scripts/create_hide_my_email.sh`
  Best-effort macOS UI automation for `系统设置 -> iCloud -> 隐藏邮件地址 -> 创建新地址`
- `scripts/get_latest_openai_code.applescript`
  Reads the newest six-digit OpenAI / ChatGPT code from recent inbox items
- `scripts/register_chatgpt.sh`
  Drives the browser registration flow with Playwright CLI
- `scripts/ocr_text.swift`
  OCR helper used by the System Settings automation to find clickable labels on screen

## Output Contract

The registration script prints:

- `REGISTERED_EMAIL=...`
- `PASSWORD=...`
- `PLAYWRIGHT_SESSION=...`

The Hide My Email script prints the newly created relay address on success.

## Reference

For the exact high-level sequence behind this implementation, read:

- `references/implementation-flow.md`
