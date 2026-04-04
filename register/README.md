# Codexbar OpenAI Workflows

This folder now contains a repeatable end-to-end workflow for adding OpenAI accounts into local `codexbar`.

There are two main lanes:

1. Import an existing OpenAI account into Codexbar
2. Create a new OpenAI account on this Mac, then import it into Codexbar

The current Codexbar build auto-listens on `http://localhost:1455/auth/callback` while the OAuth window is open, so the browser callback no longer needs to be copied back by hand.

## Prerequisites

- `codexbar.app` is installed at `/Applications/codexbar.app`
- `playwright-cli` is installed
- `Mail.app` is configured and can receive OpenAI verification emails
- `System Events` automation is enabled
- For anonymous registration: iCloud+ Hide My Email is available
- `swift` is available for the AX-based Hide My Email helper

## Existing Account Import

Use an already-existing OpenAI account and add it to Codexbar without switching the current active account:

```bash
OPENAI_EMAIL="you@example.com" \
OPENAI_PASSWORD="your-password" \
./register/scripts/import_openai_account_to_codexbar.sh
```

Expected result:

- browser login is completed automatically
- Codexbar captures the localhost callback automatically
- the account is imported into `~/.codexbar/config.json`
- the previously active account stays active

## Create And Import A New Account

Create a fresh Hide My Email alias, register a new OpenAI account, then import that new account into Codexbar:

```bash
./register/scripts/create_and_import_openai_account.sh
```

Optional overrides:

```bash
HIDE_MY_EMAIL_LABEL="codex" \
ACCOUNT_NAME="River Vale" \
BIRTH_YEAR="1990" \
BIRTH_MONTH="01" \
BIRTH_DAY="08" \
./register/scripts/create_and_import_openai_account.sh
```

Expected result:

- a new relay address is created
- a new OpenAI account is registered
- the generated credentials are reused to import the account into Codexbar
- the account is added to Codexbar without switching the active one

## Notes

- `register/chatgpt-anon-register/scripts/create_hide_my_email.sh` is now a pure launcher around `register/chatgpt-anon-register/scripts/create_hide_my_email_ax.swift`.
- The Hide My Email helper resumes from the current `System Settings` state:
  - if `System Settings` is closed, it opens it
  - if `iCloud` is already open, it continues from there
  - otherwise it deep-links directly into the Apple Account `iCloud` pane
- Hide My Email creation no longer depends on OCR, screenshots, or `cliclick`.
- `register/chatgpt-anon-register/scripts/register_chatgpt.sh` now starts from `about:blank` in an isolated Playwright session and then navigates into `chatgpt.com`.
- The ChatGPT signup entry currently has at least two UI variants on this Mac:
  - `免费注册`
  - `更多选项 -> 电子邮件地址 -> 继续`
- The signup script waits for a new Mail verification code instead of immediately reusing the mailbox's previous latest code.
- For the current automation target, the signup script stops as soon as email verification succeeds and the flow leaves the verification page.
- Existing-account import uses `register/scripts/get_codexbar_auth_url.swift` to read the active OAuth URL from the Codexbar login window.
- Email verification codes are read through `register/chatgpt-anon-register/scripts/get_latest_openai_code.applescript`.
- On this Mac, keep custom `PLAYWRIGHT_SESSION` names short; long names can fail before browser launch because the local daemon socket path becomes invalid.
- If OpenAI changes its login flow or demands stronger verification such as phone checks, the browser automation may need adjustment.
