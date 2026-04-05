#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSV_PATH="$ROOT_DIR/codex.csv"
IMPORT_SCRIPT="$ROOT_DIR/scripts/import_openai_account_to_codexbar.sh"
CSV_SHADOW_HELPER="$ROOT_DIR/scripts/codex_csv_shadow.sh"
EMAIL_FILTER="${EMAIL_FILTER:-}"
LOGIN_INTERVAL_SECS="${LOGIN_INTERVAL_SECS:-150}"
IMPORTED_COUNT=0
FAILED_COUNT=0
PENDING_FILE="$(mktemp)"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 127
  }
}

cleanup() {
  rm -f "$PENDING_FILE"
}

trap cleanup EXIT

update_csv_status() {
  local email="$1"
  local password="$2"
  local status="$3"

  codex_csv_begin_mutation "$CSV_PATH"
  python3 - "$CSV_PATH" "$email" "$password" "$status" <<'PY'
import csv
import sys

path, email, password, status = sys.argv[1:]

with open(path, "r", encoding="utf-8", newline="") as fh:
    rows = list(csv.reader(fh))

if not rows:
    rows = [["email", "password", "status", "url"]]

target_index = None
for idx in range(len(rows) - 1, 0, -1):
    row = rows[idx]
    while len(row) < 4:
        row.append("")
    if row[0] == email:
        target_index = idx
        break

if target_index is None:
    rows.append([email, password, status, ""])
else:
    existing = rows[target_index]
    while len(existing) < 4:
        existing.append("")
    rows[target_index] = [
        email,
        password if password else existing[1],
        status if status else existing[2],
        existing[3],
    ]

with open(path, "w", encoding="utf-8", newline="") as fh:
    csv.writer(fh).writerows(rows)
PY
  codex_csv_sync_shadow "$CSV_PATH"
}

require_cmd python3
source "$CSV_SHADOW_HELPER"
codex_csv_restore_if_needed "$CSV_PATH"

if [[ ! "$LOGIN_INTERVAL_SECS" =~ ^[0-9]+$ ]]; then
  printf 'LOGIN_INTERVAL_SECS must be a non-negative integer, got %s\n' "$LOGIN_INTERVAL_SECS" >&2
  exit 64
fi

python3 - "$CSV_PATH" "$EMAIL_FILTER" >"$PENDING_FILE" <<'PY'
import csv
import json
import os
import sys

csv_path, email_filter = sys.argv[1:]
cfg_path = os.path.expanduser('~/.codexbar/config.json')

with open(cfg_path, 'r', encoding='utf-8') as fh:
    cfg = json.load(fh)

imported = {
    account.get('email')
    for provider in cfg.get('providers', [])
    if provider.get('kind') == 'openai_oauth'
    for account in provider.get('accounts', [])
}

with open(csv_path, 'r', encoding='utf-8', newline='') as fh:
    rows = list(csv.DictReader(fh))

for row in rows:
    email = row.get('email', '')
    password = row.get('password', '')
    if not email or not password:
        continue
    if email_filter and email != email_filter:
        continue
    if email in imported:
        continue
    print(email)
    print(password)
PY

readarray -t TARGETS <"$PENDING_FILE"

if (( ${#TARGETS[@]} < 2 )); then
  if [[ -n "$EMAIL_FILTER" ]]; then
    printf 'no pending Codexbar import account found in %s for %s\n' "$CSV_PATH" "$EMAIL_FILTER" >&2
  else
    printf 'no pending Codexbar import account found in %s\n' "$CSV_PATH" >&2
  fi
  exit 1
fi

total=$(( ${#TARGETS[@]} / 2 ))
index=0

while (( index < ${#TARGETS[@]} )); do
  email="${TARGETS[index]}"
  password="${TARGETS[index + 1]}"
  item=$(( index / 2 + 1 ))

  printf 'IMPORT_PHASE_ITEM=%s/%s\n' "$item" "$total"

  if output="$(CODEX_CSV_PATH="$CSV_PATH" CODEX_CSV_EMAIL="$email" OPENAI_EMAIL="$email" OPENAI_PASSWORD="$password" "$IMPORT_SCRIPT" 2>&1)"; then
    printf '%s\n' "$output"
    update_csv_status "$email" "$password" "success"
    ((IMPORTED_COUNT += 1))
  else
    printf '%s\n' "$output" >&2
    update_csv_status "$email" "$password" "import_failed"
    ((FAILED_COUNT += 1))
  fi

  index=$(( index + 2 ))

  if (( index < ${#TARGETS[@]} && LOGIN_INTERVAL_SECS > 0 )); then
    printf 'WAIT_BEFORE_NEXT_IMPORT_SECS=%s\n' "$LOGIN_INTERVAL_SECS"
    sleep "$LOGIN_INTERVAL_SECS"
  fi
done

printf 'BATCH_IMPORTED_COUNT=%s\n' "$IMPORTED_COUNT"
printf 'BATCH_FAILED_COUNT=%s\n' "$FAILED_COUNT"

if (( FAILED_COUNT > 0 )); then
  exit 1
fi
