#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HIDE_MY_EMAIL_SCRIPT="$ROOT_DIR/chatgpt-anon-register/scripts/create_hide_my_email.sh"
REGISTER_SCRIPT="$ROOT_DIR/chatgpt-anon-register/scripts/register_chatgpt.sh"
IMPORT_SCRIPT="$ROOT_DIR/scripts/import_openai_account_to_codexbar.sh"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 127
  }
}

require_cmd bash

RELAY_EMAIL="$("$HIDE_MY_EMAIL_SCRIPT")"
if [[ -z "$RELAY_EMAIL" ]]; then
  printf 'failed to create a new Hide My Email alias\n' >&2
  exit 1
fi

REGISTER_OUTPUT="$(RELAY_EMAIL="$RELAY_EMAIL" "$REGISTER_SCRIPT")"
REGISTERED_EMAIL="$(printf '%s\n' "$REGISTER_OUTPUT" | sed -n 's/^REGISTERED_EMAIL=//p' | tail -n 1)"
PASSWORD="$(printf '%s\n' "$REGISTER_OUTPUT" | sed -n 's/^PASSWORD=//p' | tail -n 1)"

if [[ -z "$REGISTERED_EMAIL" || -z "$PASSWORD" ]]; then
  printf 'failed to parse registration output\n' >&2
  printf '%s\n' "$REGISTER_OUTPUT" >&2
  exit 1
fi

OPENAI_EMAIL="$REGISTERED_EMAIL" OPENAI_PASSWORD="$PASSWORD" "$IMPORT_SCRIPT"

printf 'REGISTERED_EMAIL=%s\n' "$REGISTERED_EMAIL"
printf 'PASSWORD=%s\n' "$PASSWORD"
