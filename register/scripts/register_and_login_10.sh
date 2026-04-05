#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTER_SCRIPT="$SCRIPT_DIR/create_and_import_openai_account.sh"
RETRY_IMPORT_SCRIPT="$SCRIPT_DIR/retry_codexbar_import_from_csv.sh"
CSV_PATH="$SCRIPT_DIR/../codex.csv"
TOTAL_ACCOUNTS=10
FAILED_EMAILS=()
SUCCESS_COUNT=0

get_last_failed_email() {
  python3 - "$CSV_PATH" <<'PY'
import csv
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8", newline="") as fh:
    rows = list(csv.reader(fh))

# Find the last row with non-success status (skip header)
for idx in range(len(rows) - 1, 0, -1):
    row = rows[idx]
    if len(row) >= 3 and row[2] not in ("success", "IMPORTED", ""):
        print(row[0])
        break
PY
}

for i in $(seq 1 "$TOTAL_ACCOUNTS"); do
  printf '\n========== [%d/%d] Starting registration and import ==========\n' "$i" "$TOTAL_ACCOUNTS"
  
  if REGISTRATION_SETTLE_SECS=60 "$REGISTER_SCRIPT"; then
    printf '========== [%d/%d] SUCCESS ==========\n' "$i" "$TOTAL_ACCOUNTS"
    ((SUCCESS_COUNT++))
  else
    EXIT_CODE=$?
    printf '========== [%d/%d] FAILED (exit %d) - recording for retry ==========\n' "$i" "$TOTAL_ACCOUNTS" "$EXIT_CODE"
    # Extract the email from the CSV for the failed row
    FAILED_EMAIL="$(get_last_failed_email)"
    if [[ -n "$FAILED_EMAIL" ]]; then
      FAILED_EMAILS+=("$FAILED_EMAIL")
      printf 'Failed email: %s\n' "$FAILED_EMAIL"
    fi
  fi
  
  # Add a small delay between registrations to avoid rate limiting
  if (( i < TOTAL_ACCOUNTS )); then
    printf 'Waiting 10 seconds before next registration...\n'
    sleep 10
  fi
done

printf '\n\n========== SUMMARY ==========\n'
printf 'Total attempted: %d\n' "$TOTAL_ACCOUNTS"
printf 'Success: %d\n' "$SUCCESS_COUNT"
printf 'Failed count: %d\n' "${#FAILED_EMAILS[@]}"

if (( ${#FAILED_EMAILS[@]} > 0 )); then
  printf '\nFailed emails (will retry import):\n'
  for email in "${FAILED_EMAILS[@]}"; do
    printf '  - %s\n' "$email"
  done
  
  printf '\n\nRetrying failed imports...\n'
  RETRY_SUCCESS=0
  for email in "${FAILED_EMAILS[@]}"; do
    printf '\nRetrying import for: %s\n' "$email"
    # Extract password from CSV
    PASSWORD="$(python3 - "$CSV_PATH" "$email" <<'PY'
import csv
import sys

path, target_email = sys.argv[1:]
with open(path, "r", encoding="utf-8", newline="") as fh:
    rows = list(csv.reader(fh))

for row in rows[1:]:
    if row[0] == target_email:
        print(row[1])
        break
PY
)"
    if [[ -n "$PASSWORD" ]]; then
      if OPENAI_EMAIL="$email" OPENAI_PASSWORD="$PASSWORD" REGISTRATION_SETTLE_SECS=60 "$RETRY_IMPORT_SCRIPT"; then
        printf 'Retry import for %s: SUCCESS\n' "$email"
        ((RETRY_SUCCESS++))
      else
        printf 'Retry import for %s: FAILED\n' "$email" >&2
      fi
    fi
  done
  printf '\nRetry summary: %d/%d succeeded\n' "$RETRY_SUCCESS" "${#FAILED_EMAILS[@]}"
fi

printf '\n========== ALL DONE ==========\n'
