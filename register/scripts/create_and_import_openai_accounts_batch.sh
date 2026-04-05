#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSV_PATH="$ROOT_DIR/codex.csv"
CREATE_SCRIPT="$ROOT_DIR/scripts/create_and_import_openai_account.sh"
IMPORT_SCRIPT="$ROOT_DIR/scripts/import_openai_account_to_codexbar.sh"
CSV_SHADOW_HELPER="$ROOT_DIR/scripts/codex_csv_shadow.sh"
BATCH_SIZE="${BATCH_SIZE:-5}"
IMPORT_PHASE_DELAY_SECS="${IMPORT_PHASE_DELAY_SECS:-0}"
ACCOUNTS_FILE="$(mktemp)"

REGISTERED_COUNT=0
IMPORTED_COUNT=0
REGISTRATION_FAILURE=0
IMPORT_FAILURE=0

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 127
  }
}

cleanup() {
  rm -f "$ACCOUNTS_FILE"
}

trap cleanup EXIT

ensure_positive_integer() {
  local name="$1"
  local value="$2"

  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s must be a positive integer, got %s\n' "$name" "$value" >&2
    exit 64
  fi
}

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

require_cmd bash
require_cmd python3
source "$CSV_SHADOW_HELPER"

ensure_positive_integer "BATCH_SIZE" "$BATCH_SIZE"

if [[ ! "$IMPORT_PHASE_DELAY_SECS" =~ ^[0-9]+$ ]]; then
  printf 'IMPORT_PHASE_DELAY_SECS must be a non-negative integer, got %s\n' "$IMPORT_PHASE_DELAY_SECS" >&2
  exit 64
fi

for index in $(seq 1 "$BATCH_SIZE"); do
  printf 'REGISTER_PHASE_ITEM=%s/%s\n' "$index" "$BATCH_SIZE"
  if ! output="$(IMPORT_AFTER_REGISTER=0 "$CREATE_SCRIPT" 2>&1)"; then
    printf '%s\n' "$output" >&2
    REGISTRATION_FAILURE=1
    break
  fi

  printf '%s\n' "$output"

  email="$(printf '%s\n' "$output" | sed -n 's/^REGISTERED_EMAIL=//p' | tail -n 1)"
  password="$(printf '%s\n' "$output" | sed -n 's/^PASSWORD=//p' | tail -n 1)"

  if [[ -z "$email" || -z "$password" ]]; then
    printf 'failed to parse registration output for batch item %s\n' "$index" >&2
    REGISTRATION_FAILURE=1
    break
  fi

  printf '%s\t%s\n' "$email" "$password" >>"$ACCOUNTS_FILE"
  ((REGISTERED_COUNT += 1))
done

if (( REGISTERED_COUNT == 0 )); then
  printf 'no accounts were registered; skipping import phase\n' >&2
  exit 1
fi

if (( IMPORT_PHASE_DELAY_SECS > 0 )); then
  sleep "$IMPORT_PHASE_DELAY_SECS"
fi

index=0
while IFS=$'\t' read -r email password; do
  ((index += 1))
  printf 'IMPORT_PHASE_ITEM=%s/%s\n' "$index" "$REGISTERED_COUNT"
  if output="$(CODEX_CSV_PATH="$CSV_PATH" CODEX_CSV_EMAIL="$email" OPENAI_EMAIL="$email" OPENAI_PASSWORD="$password" "$IMPORT_SCRIPT" 2>&1)"; then
    printf '%s\n' "$output"
    update_csv_status "$email" "$password" "success"
    ((IMPORTED_COUNT += 1))
    continue
  fi

  printf '%s\n' "$output" >&2
  update_csv_status "$email" "$password" "import_failed"
  IMPORT_FAILURE=1
done <"$ACCOUNTS_FILE"

printf 'BATCH_REGISTERED_COUNT=%s\n' "$REGISTERED_COUNT"
printf 'BATCH_IMPORTED_COUNT=%s\n' "$IMPORTED_COUNT"

if (( REGISTRATION_FAILURE || IMPORT_FAILURE )); then
  exit 1
fi
