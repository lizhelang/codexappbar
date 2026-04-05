#!/usr/bin/env bash

if [[ -n "${CODEX_CSV_SHADOW_HELPER_LOADED:-}" ]]; then
  return 0
fi
CODEX_CSV_SHADOW_HELPER_LOADED=1

CODEX_CSV_SHADOW_PATH="${CODEX_CSV_SHADOW_PATH:-$HOME/.codexbar/register-codex.csv}"
CODEX_CSV_SNAPSHOT_DIR="${CODEX_CSV_SNAPSHOT_DIR:-$HOME/.codexbar/register-codex-history}"
CODEX_CSV_SNAPSHOT_DONE=0

codex_csv_sync_global_shadow() {
  local csv_path="$1"

  [[ -f "$csv_path" ]] || return 0
  mkdir -p "$(dirname "$CODEX_CSV_SHADOW_PATH")"
  cp "$csv_path" "$CODEX_CSV_SHADOW_PATH"
}

codex_csv_restore_if_needed() {
  local csv_path="$1"

  if [[ -f "$csv_path" || ! -f "$CODEX_CSV_SHADOW_PATH" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$csv_path")"
  cp "$CODEX_CSV_SHADOW_PATH" "$csv_path"
}

codex_csv_snapshot_once() {
  local csv_path="$1"
  local stamp=""

  if [[ "$CODEX_CSV_SNAPSHOT_DONE" == "1" || ! -f "$csv_path" ]]; then
    return 0
  fi

  mkdir -p "$CODEX_CSV_SNAPSHOT_DIR"
  stamp="$(date '+%Y%m%d-%H%M%S')"
  cp "$csv_path" "$CODEX_CSV_SNAPSHOT_DIR/codex-${stamp}.csv"
  CODEX_CSV_SNAPSHOT_DONE=1
}

codex_csv_sync_shadow() {
  local csv_path="$1"

  [[ -f "$csv_path" ]] || return 0

  codex_csv_sync_global_shadow "$csv_path"
}

codex_csv_begin_mutation() {
  local csv_path="$1"

  codex_csv_restore_if_needed "$csv_path"
  codex_csv_snapshot_once "$csv_path"
}

codex_csv_checkout_sync() {
  local csv_path="$1"

  if [[ -f "$csv_path" ]]; then
    codex_csv_sync_global_shadow "$csv_path"
    return 0
  fi

  codex_csv_restore_if_needed "$csv_path"
}
