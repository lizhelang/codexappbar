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

- Existing-account import uses `register/scripts/get_codexbar_auth_url.swift` to read the active OAuth URL from the Codexbar login window.
- Email verification codes are read through `register/chatgpt-anon-register/scripts/get_latest_openai_code.applescript`.
- If OpenAI changes its login flow or demands stronger verification such as phone checks, the browser automation may need adjustment.
