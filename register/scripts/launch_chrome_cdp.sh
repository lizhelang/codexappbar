#!/usr/bin/env bash

set -euo pipefail

PORT="${PORT:-9222}"
USER_DATA_DIR="${USER_DATA_DIR:-/tmp/codexbar-cdp-${PORT}}"
STARTUP_URL="${STARTUP_URL:-about:blank}"

open -n -a "Google Chrome" --args \
  --remote-debugging-port="$PORT" \
  --user-data-dir="$USER_DATA_DIR" \
  --incognito \
  "$STARTUP_URL"

deadline=$((SECONDS + 20))
while (( SECONDS < deadline )); do
  if curl -fsS "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

curl -fsS "http://127.0.0.1:${PORT}/json/version"
