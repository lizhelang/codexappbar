#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CREATE_SCRIPT="$ROOT_DIR/scripts/create_and_import_openai_account.sh"
CSV_PATH="$ROOT_DIR/codex.csv"
LOG_FILE="$ROOT_DIR/register_100.log"
TOTAL_TARGET=100
REGISTRATION_SETTLE_SECS=180

export REGISTRATION_SETTLE_SECS

# Count existing successful accounts
existing_success=$(python3 -c "
import csv
with open('$CSV_PATH', 'r', encoding='utf-8', newline='') as fh:
    rows = list(csv.DictReader(fh))
print(sum(1 for r in rows if r.get('status') == 'success'))
")

printf 'Existing successful accounts: %s\n' "$existing_success" | tee -a "$LOG_FILE"

remaining=$((TOTAL_TARGET - existing_success))
if (( remaining <= 0 )); then
  printf 'Already have %s successful accounts, target is %s\n' "$existing_success" "$TOTAL_TARGET" | tee -a "$LOG_FILE"
  exit 0
fi

printf 'Need to register %s more accounts to reach %s\n' "$remaining" "$TOTAL_TARGET" | tee -a "$LOG_FILE"

success_count=0
failed_reg=0
failed_import=0
attempt=0

while (( success_count < remaining )); do
  attempt=$((attempt + 1))
  current_total=$((existing_success + success_count))
  printf '\n========== ATTEMPT %d | TARGET %d/%d | CURRENT SUCCESS: %d ==========\n' \
    "$attempt" "$((success_count + 1))" "$remaining" "$current_total" | tee -a "$LOG_FILE"
  
  if output="$(REGISTRATION_SETTLE_SECS=180 "$CREATE_SCRIPT" 2>&1)"; then
    email="$(printf '%s\n' "$output" | sed -n 's/^REGISTERED_EMAIL=//p' | tail -n 1)"
    printf 'SUCCESS: %s\n' "$email" | tee -a "$LOG_FILE"
    ((success_count += 1))
  else
    exit_code=$?
    printf 'FAILED (exit %d): attempt %d\n' "$exit_code" "$attempt" | tee -a "$LOG_FILE"
    printf '%s\n' "$output" | tail -5 | tee -a "$LOG_FILE"
    
    if echo "$output" | grep -q "hide_my_email_failed\|registration_parse_failed"; then
      ((failed_reg += 1))
    else
      ((failed_import += 1))
    fi
  fi
  
  if (( success_count < remaining )); then
    printf '\nWaiting 10 seconds before next registration...\n' | tee -a "$LOG_FILE"
    sleep 10
  fi
done

printf '\n========== FINAL SUMMARY ==========\n' | tee -a "$LOG_FILE"
printf 'New successful accounts: %d\n' "$success_count" | tee -a "$LOG_FILE"
printf 'Registration failures: %d\n' "$failed_reg" | tee -a "$LOG_FILE"
printf 'Import failures: %d\n' "$failed_import" | tee -a "$LOG_FILE"
printf 'Total attempts: %d\n' "$attempt" | tee -a "$LOG_FILE"

# Final count
final_success=$(python3 -c "
import csv
with open('$CSV_PATH', 'r', encoding='utf-8', newline='') as fh:
    rows = list(csv.DictReader(fh))
print(sum(1 for r in rows if r.get('status') == 'success'))
")
printf 'Total successful accounts in CSV: %d\n' "$final_success" | tee -a "$LOG_FILE"
