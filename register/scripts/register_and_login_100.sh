#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CREATE_AND_IMPORT_SCRIPT="$ROOT_DIR/scripts/create_and_import_openai_account.sh"
TOTAL_ACCOUNTS="${1:-100}"
SUCCESS_COUNT=0
FAILED_COUNT=0
FAILED_EMAILS_FILE="$(mktemp)"

cleanup() {
  rm -f "$FAILED_EMAILS_FILE"
}

trap cleanup EXIT

printf '开始注册并导入 %s 个账号\n' "$TOTAL_ACCOUNTS"
printf '注册和登录间隔: 180 秒\n'
printf '========================================\n'

for i in $(seq 1 "$TOTAL_ACCOUNTS"); do
  printf '\n[%s/%s] 开始注册账号...\n' "$i" "$TOTAL_ACCOUNTS"
  
  if REGISTRATION_SETTLE_SECS=180 "$CREATE_AND_IMPORT_SCRIPT"; then
    printf '✅ 账号 %s 注册并导入成功\n' "$i"
    ((SUCCESS_COUNT += 1))
  else
    printf '❌ 账号 %s 注册或导入失败\n' "$i"
    ((FAILED_COUNT += 1))
    # 记录失败的邮箱以便后续处理
    if [[ -f "$ROOT_DIR/codex.csv" ]]; then
      # 获取最后一条失败记录
      tail -n 1 "$ROOT_DIR/codex.csv" | grep -v "email" >> "$FAILED_EMAILS_FILE" 2>/dev/null || true
    fi
  fi
  
  # 在每次尝试之间稍微停顿,避免过快连续
  if (( i < TOTAL_ACCOUNTS )); then
    printf '等待 10 秒后继续下一个账号...\n'
    sleep 10
  fi
done

printf '\n========================================\n'
printf '任务完成!\n'
printf '成功: %s\n' "$SUCCESS_COUNT"
printf '失败: %s\n' "$FAILED_COUNT"

if (( FAILED_COUNT > 0 )) && [[ -f "$FAILED_EMAILS_FILE" ]]; then
  printf '\n失败的账号邮箱:\n'
  cat "$FAILED_EMAILS_FILE"
fi

if (( FAILED_COUNT > 0 )); then
  exit 1
fi
