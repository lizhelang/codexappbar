#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTER_SCRIPT="$SCRIPT_DIR/create_and_import_openai_account.sh"
CSV_PATH="$SCRIPT_DIR/../codex.csv"
TOTAL_ACCOUNTS=10
SUCCESS_COUNT=0
FAIL_COUNT=0

for i in $(seq 1 "$TOTAL_ACCOUNTS"); do
  printf '\n========== [%d/%d] Starting registration and import ==========\n' "$i" "$TOTAL_ACCOUNTS"
  
  if REGISTRATION_SETTLE_SECS=60 "$REGISTER_SCRIPT"; then
    printf '========== [%d/%d] SUCCESS ==========\n' "$i" "$TOTAL_ACCOUNTS"
    ((SUCCESS_COUNT++))
  else
    EXIT_CODE=$?
    printf '========== [%d/%d] FAILED (exit %d) ==========\n' "$i" "$TOTAL_ACCOUNTS" "$EXIT_CODE"
    ((FAIL_COUNT++))
  fi
  
  # Add a small delay between registrations to avoid rate limiting
  if (( i < TOTAL_ACCOUNTS )); then
    printf 'Waiting 10 seconds before next registration...\n'
    sleep 10
  fi
done

printf '\n\n========== FINAL SUMMARY ==========\n'
printf 'Total: %d | Success: %d | Failed: %d\n' "$TOTAL_ACCOUNTS" "$SUCCESS_COUNT" "$FAIL_COUNT"
printf '=====================================\n'
