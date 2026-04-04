---
name: chatgpt-anon-register
description: Create a pseudonymous ChatGPT account on macOS by generating a new iCloud Hide My Email alias, reading the OpenAI verification code from Mail.app, and driving the browser signup flow without using the user's real identity.
---

# ChatGPT Anonymous Registration

Use this skill when the task is specifically:

- create a new ChatGPT account with a fresh iCloud Hide My Email alias
- keep the flow pseudonymous instead of using the user's real name or birthday
- run on macOS with `System Settings`, `Mail.app`, `swift`, and `playwright-cli`

Do not use this skill for:

- paid upgrades, purchases, or billing setup
- flows that require phone verification, ID checks, or other stronger identity binding
- non-macOS environments

## Preconditions

- Signed in to iCloud on the local Mac
- `隐藏邮件地址` / Hide My Email is available under iCloud+
- `Mail.app` is configured and can receive the forwarded relay mail
- Accessibility automation is enabled for `System Events`
- `swift`, `osascript`, and `playwright-cli` are installed
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

- start from a blank isolated Playwright browser session and enter the `chatgpt.com` signup path
- handle the currently observed `免费注册` and `更多选项 -> 电子邮件地址 -> 继续` entry variants
- generate a strong password only when the password path is actually needed
- wait for a new OpenAI verification code from `Mail.app` instead of immediately reusing the mailbox's previous latest code
- stop once email verification succeeds and the flow leaves the verification page

4. To import the new account into local Codexbar without switching the current active account:

```bash
./register/scripts/create_and_import_openai_account.sh
```

## Scripts

- `scripts/create_hide_my_email.sh`
  Shell entry point for the pure-code Hide My Email creator
- `scripts/create_hide_my_email_ax.swift`
  AX-based state machine for `System Settings -> iCloud -> Hide My Email -> create address`
- `scripts/get_latest_openai_code.applescript`
  Reads the newest six-digit OpenAI / ChatGPT code from recent inbox items
- `scripts/register_chatgpt.sh`
  Drives the browser registration flow with Playwright CLI, preferring one-time-code signup when that option is present

## Output Contract

The registration script prints:

- `REGISTERED_EMAIL=...`
- `PASSWORD=...`
- `PLAYWRIGHT_SESSION=...`

The Hide My Email script prints the newly created relay address on success.

Implementation note:

- The Hide My Email flow is now Accessibility-first and resumes from the current `System Settings` state when possible.
- Keep `PLAYWRIGHT_SESSION` names short on this Mac; long names can fail before browser launch because of local daemon socket path limits.

## Reference

For the exact high-level sequence behind this implementation, read:

- `references/implementation-flow.md`
