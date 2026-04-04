#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTH_URL_SCRIPT="$ROOT_DIR/scripts/get_codexbar_auth_url.swift"
COPY_AUTH_URL_SCRIPT="$ROOT_DIR/scripts/copy_codexbar_auth_url.swift"
SAFARI_AUTH_URL_SCRIPT="$ROOT_DIR/scripts/get_codexbar_safari_auth_url.applescript"
MAIL_CODE_SCRIPT="$ROOT_DIR/chatgpt-anon-register/scripts/get_latest_openai_code.applescript"
CODEXBAR_APP="${CODEXBAR_APP:-/Applications/codexbar.app}"
PLAYWRIGHT_SESSION_RAW="${PLAYWRIGHT_SESSION:-ci$(date +%H%M%S)}"
OPENAI_EMAIL="${OPENAI_EMAIL:-}"
OPENAI_PASSWORD="${OPENAI_PASSWORD:-}"
CODEX_AUTH_URL_FILE="${CODEX_AUTH_URL_FILE:-}"
CODEX_CSV_PATH="${CODEX_CSV_PATH:-}"
CODEX_CSV_EMAIL="${CODEX_CSV_EMAIL:-$OPENAI_EMAIL}"
ACCOUNT_NAME="${ACCOUNT_NAME:-River Vale}"
BIRTH_YEAR="${BIRTH_YEAR:-1990}"
BIRTH_MONTH="${BIRTH_MONTH:-01}"
BIRTH_DAY="${BIRTH_DAY:-08}"
AGE="${AGE:-}"
KEEP_PLAYWRIGHT_SESSION="${KEEP_PLAYWRIGHT_SESSION:-0}"
PREFER_EMAIL_OTP_LOGIN="${PREFER_EMAIL_OTP_LOGIN:-1}"
ALLOW_SAFARI_AUTH_URL_FALLBACK="${ALLOW_SAFARI_AUTH_URL_FALLBACK:-0}"
TEST_OAUTH_NAV_ONLY="${TEST_OAUTH_NAV_ONLY:-0}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 127
  }
}

sanitize_session() {
  local raw="$1"
  local clean
  clean="$(printf '%s' "$raw" | tr -cd 'A-Za-z0-9._-' | cut -c1-12)"
  if [[ -z "$clean" ]]; then
    clean="ci$(date +%H%M%S)"
  fi
  printf '%s\n' "$clean"
}

js_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

extract_eval_json() {
  python3 -c '
import json
import re
import sys

text = sys.stdin.read()
match = re.search(r"### Result\s*(.*?)\s*(?:### Ran Playwright code|### Page|$)", text, re.S)
if not match:
    sys.stderr.write(text)
    raise SystemExit(1)

payload = match.group(1).strip()
decoded = json.loads(payload)
if isinstance(decoded, str):
    print(decoded)
else:
    print(json.dumps(decoded, ensure_ascii=False))
'
}

load_state_vars() {
  local json_text="$1"
  eval "$(
    python3 - "$json_text" <<'PY'
import json
import shlex
import sys

state = json.loads(sys.argv[1])
for key, value in state.items():
    name = key.upper()
    if isinstance(value, bool):
        print(f"{name}={'1' if value else '0'}")
    elif value is None:
        print(f"{name}=''")
    else:
        print(f"{name}={shlex.quote(str(value))}")
PY
  )"
}

latest_code() {
  osascript "$MAIL_CODE_SCRIPT" 2>/dev/null | tr -d '\r\n'
}

wait_for_new_code() {
  local baseline="$1"
  local timeout_secs="${2:-60}"
  local code=""
  local deadline=$((SECONDS + timeout_secs))

  while (( SECONDS < deadline )); do
    code="$(latest_code || true)"
    if [[ "$code" =~ ^[0-9]{6}$ && "$code" != "$baseline" ]]; then
      printf '%s\n' "$code"
      return 0
    fi
    sleep 3
  done

  return 1
}

wait_for_auth_url() {
  swift "$AUTH_URL_SCRIPT" 2>/dev/null
}

copy_auth_url() {
  swift "$COPY_AUTH_URL_SCRIPT" 2>/dev/null
}

wait_for_safari_auth_url() {
  osascript "$SAFARI_AUTH_URL_SCRIPT" 2>/dev/null
}

wait_for_account_import() {
  local email="$1"
  local timeout_secs="${2:-120}"
  local deadline=$((SECONDS + timeout_secs))

  while (( SECONDS < deadline )); do
    if python3 - "$email" /Users/lzl/.codexbar/config.json <<'PY'
import json, sys

target = sys.argv[1]
config_path = sys.argv[2]

with open(config_path, 'r', encoding='utf-8') as fh:
    config = json.load(fh)

for provider in config.get("providers", []):
    for item in provider.get("accounts", []):
        if item.get("email") == target:
            raise SystemExit(0)
raise SystemExit(1)
PY
    then
      return 0
    fi
    sleep 1
  done

  printf 'timed out waiting for Codexbar to import account %s\n' "$email" >&2
  return 1
}

update_codex_csv_url() {
  [[ -n "$CODEX_CSV_PATH" && -n "$CODEX_CSV_EMAIL" ]] || return 0

  python3 - "$CODEX_CSV_PATH" "$CODEX_CSV_EMAIL" "$1" <<'PY'
import csv
import sys

path, email, url = sys.argv[1:]

with open(path, "r", encoding="utf-8", newline="") as fh:
    rows = list(csv.reader(fh))

if not rows:
    raise SystemExit(0)

for idx in range(len(rows) - 1, 0, -1):
    row = rows[idx]
    while len(row) < 4:
        row.append("")
    if row[0] == email:
        row[3] = url
        rows[idx] = row
        break
else:
    rows.append([email, "", "", url])

with open(path, "w", encoding="utf-8", newline="") as fh:
    csv.writer(fh).writerows(rows)
PY
}

SESSION="$(sanitize_session "$PLAYWRIGHT_SESSION_RAW")"

pw() {
  playwright-cli --session "$SESSION" "$@"
}

run_code() {
  local snippet="$1"
  pw run-code "$snippet" >/dev/null
}

eval_json() {
  local expr="$1"
  pw eval "$expr" | extract_eval_json
}

current_state_json() {
  eval_json "$(cat <<'JS'
() => JSON.stringify((() => {
  const bodyText = (document.body?.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 7000);
  const lowered = bodyText.toLowerCase();
  const isVisible = (el) => {
    if (!el) return false;
    const style = window.getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
  };
  const visible = (selector) => [...document.querySelectorAll(selector)].filter(isVisible);
  const attrs = (el) => [
    el.getAttribute('aria-label') || '',
    el.getAttribute('placeholder') || '',
    el.getAttribute('name') || '',
    el.getAttribute('autocomplete') || '',
    el.id || '',
    el.textContent || '',
  ].join(' ').toLowerCase();
  const visibleInputs = visible('input, textarea, [role="spinbutton"]');
  const emailInput = visibleInputs.some((el) => /电子邮件地址|email/.test(attrs(el)));
  const passwordInput = visibleInputs.some((el) => /密码|password/.test(attrs(el)) || el.matches?.('input[type="password"]'));
  const codeInput = visibleInputs.some((el) => /验证码|code/.test(attrs(el)) || String(el.maxLength) === '6' || String(el.maxLength) === '1' || el.matches?.('input[autocomplete="one-time-code"]'));
  const otpLoginOption = /使用一次性验证码登录|one-time passcode|one-time code|email code/.test(lowered);
  const consentContinue = /sign-in-with-chatgpt\/codex\/consent/.test(location.href) || /允许|授权|继续/.test(lowered) && /codex|openai/.test(lowered);
  const callbackPage = /localhost:1455\/auth\/callback/.test(location.href);
  const addPhone = /\/add-phone/.test(location.href) || /电话号码是必填项|添加电话号码|phone number is required|verify phone/.test(lowered);
  const ageInput = visibleInputs.some((el) => /年龄|(^|[^a-z])age([^a-z]|$)/.test(attrs(el)));
  const yearInput = visibleInputs.some((el) => /(^|[^a-z])year([^a-z]|$)|年, /.test(attrs(el)));
  const monthInput = visibleInputs.some((el) => /(^|[^a-z])month([^a-z]|$)|月, /.test(attrs(el)));
  const dayInput = visibleInputs.some((el) => /(^|[^a-z])day([^a-z]|$)|日, /.test(attrs(el)));
  const nameInput = visibleInputs.some((el) => /全名|姓名|full name|name/.test(attrs(el)));
  return {
    href: location.href,
    title: document.title,
    bodyText,
    emailInput,
    passwordInput,
    codeInput,
    otpLoginOption,
    consentContinue,
    callbackPage,
    addPhone,
    ageInput,
    yearInput,
    monthInput,
    dayInput,
    nameInput
  };
})())
JS
)"
}

cleanup_playwright() {
  if [[ "$KEEP_PLAYWRIGHT_SESSION" == "1" ]]; then
    return
  fi
  playwright-cli session-stop "$SESSION" >/dev/null 2>&1 || true
  playwright-cli session-delete "$SESSION" >/dev/null 2>&1 || true
}

trap cleanup_playwright EXIT

if [[ -z "$OPENAI_EMAIL" ]]; then
  printf 'usage: OPENAI_EMAIL=<email> [OPENAI_PASSWORD=<password>] %s\n' "$0" >&2
  exit 64
fi

require_cmd playwright-cli
require_cmd swift
require_cmd osascript
require_cmd open
require_cmd python3

if [[ -z "$AGE" && "$BIRTH_YEAR" =~ ^[0-9]{4}$ ]]; then
  AGE="$(( $(date +%Y) - BIRTH_YEAR ))"
fi

ACCOUNT_NAME_JS="${ACCOUNT_NAME//\\/\\\\}"
ACCOUNT_NAME_JS="${ACCOUNT_NAME_JS//\"/\\\"}"
BIRTH_YEAR_JS="${BIRTH_YEAR//\\/\\\\}"
BIRTH_YEAR_JS="${BIRTH_YEAR_JS//\"/\\\"}"
BIRTH_MONTH_JS="${BIRTH_MONTH//\\/\\\\}"
BIRTH_MONTH_JS="${BIRTH_MONTH_JS//\"/\\\"}"
BIRTH_DAY_JS="${BIRTH_DAY//\\/\\\\}"
BIRTH_DAY_JS="${BIRTH_DAY_JS//\"/\\\"}"
AGE_JS="${AGE//\\/\\\\}"
AGE_JS="${AGE_JS//\"/\\\"}"
EMAIL_JS="${OPENAI_EMAIL//\\/\\\\}"
EMAIL_JS="${EMAIL_JS//\"/\\\"}"
PASSWORD_JS="${OPENAI_PASSWORD//\\/\\\\}"
PASSWORD_JS="${PASSWORD_JS//\"/\\\"}"

osascript -e 'tell application id "lzhl.codexAppBar" to activate' >/dev/null 2>&1 || open -a "$CODEXBAR_APP"
sleep 1
open 'com.codexbar.oauth://login'

AUTH_URL=""
AUTH_URL_SOURCE=""
for _ in $(seq 1 80); do
  AUTH_URL="$(copy_auth_url || true)"
  if [[ -n "$AUTH_URL" ]]; then
    AUTH_URL_SOURCE="popup_copy"
    break
  fi
  AUTH_URL="$(wait_for_auth_url || true)"
  if [[ -n "$AUTH_URL" ]]; then
    AUTH_URL_SOURCE="popup_ax"
    break
  fi

  if [[ "$ALLOW_SAFARI_AUTH_URL_FALLBACK" == "1" ]]; then
    AUTH_URL="$(wait_for_safari_auth_url || true)"
    if [[ -n "$AUTH_URL" ]]; then
      AUTH_URL_SOURCE="safari_fallback"
      break
    fi
  fi

  sleep 0.5
done

if [[ -z "$AUTH_URL" ]]; then
  if [[ "$ALLOW_SAFARI_AUTH_URL_FALLBACK" == "1" ]]; then
    printf 'failed to read the Codexbar OAuth URL from the popup or Safari fallback\n' >&2
  else
    printf 'failed to read the Codexbar OAuth URL from the popup\n' >&2
  fi
  exit 1
fi

AUTH_URL="$(printf '%s' "$AUTH_URL" | tr -d '\r\n')"

printf 'AUTH_URL_SOURCE=%s\n' "$AUTH_URL_SOURCE"
if [[ -n "$CODEX_AUTH_URL_FILE" ]]; then
  printf '%s\n' "$AUTH_URL" >"$CODEX_AUTH_URL_FILE"
fi
update_codex_csv_url "$AUTH_URL"

playwright-cli session-stop "$SESSION" >/dev/null 2>&1 || true
playwright-cli session-delete "$SESSION" >/dev/null 2>&1 || true
pw --isolated --browser chrome --headed open "$AUTH_URL" >/dev/null

if [[ "$TEST_OAUTH_NAV_ONLY" == "1" ]]; then
  printf 'OAUTH_NAVIGATION_VERIFIED=1\n'
  printf 'AUTH_URL=%s\n' "$AUTH_URL"
  exit 0
fi

mail_code_baseline="$(latest_code || true)"
code_attempts=0
resend_attempts=0
deadline=$((SECONDS + 360))
status="IN_PROGRESS"
stop_reason=""

while (( SECONDS < deadline )); do
  STATE_JSON="$(current_state_json)"
  load_state_vars "$STATE_JSON"

  if [[ "$CALLBACKPAGE" == "1" ]]; then
    if wait_for_account_import "$OPENAI_EMAIL" 120; then
      status="IMPORTED"
      break
    fi
  fi

  if [[ "$ADDPHONE" == "1" ]]; then
    status="BLOCKED"
    stop_reason="phone_verification_required"
    break
  fi

  if [[ "$CONSENTCONTINUE" == "1" ]]; then
    run_code "$(cat <<'JS'
async (page) => {
  const btn = page.getByRole('button', { name: /^(继续|Continue|Allow|允许|Authorize)$/i }).first();
  if (await btn.count()) {
    await btn.click();
  }
}
JS
)"
    sleep 2
    if wait_for_account_import "$OPENAI_EMAIL" 120; then
      status="IMPORTED"
      break
    fi
    continue
  fi

  if [[ "$PREFER_EMAIL_OTP_LOGIN" == "1" && "$OTPLOGINOPTION" == "1" ]]; then
    run_code "$(cat <<'JS'
async (page) => {
  const btn = page.getByRole('button', { name: /使用一次性验证码登录|one-time passcode|one-time code/i }).first();
  if (await btn.count()) {
    await btn.click();
    return;
  }
  throw new Error('otp login option not found');
}
JS
)"
    sleep 2
    continue
  fi

  if [[ "$CODEINPUT" == "1" ]]; then
    if (( resend_attempts < 2 )); then
      run_code "$(cat <<'JS'
async (page) => {
  const btns = [
    page.getByRole('button', { name: /重新发送电子邮件|重新发送|resend email|resend/i }),
    page.getByRole('link', { name: /重新发送电子邮件|重新发送|resend email|resend/i }),
    page.locator('button, a')
  ];
  for (const loc of btns) {
    if (await loc.count()) {
      const b = loc.first();
      const t = ((await b.textContent().catch(() => '')) || '').toLowerCase();
      if (await b.isVisible().catch(() => false) && /重新发送|resend/.test(t)) {
        await b.click();
        return;
      }
    }
  }
}
JS
)" || true
      ((resend_attempts += 1))
    fi

    CODE="$(wait_for_new_code "$mail_code_baseline" 60 || true)"
    if [[ ! "$CODE" =~ ^[0-9]{6}$ ]]; then
      sleep 3
      continue
    fi
    mail_code_baseline="$CODE"
    ((code_attempts += 1))

    run_code "$(cat <<JS
async (page) => {
  const code = "$CODE";
  const multi = page.locator('input[autocomplete=\"one-time-code\"], input[inputmode=\"numeric\"], input[maxlength=\"1\"]');
  const count = await multi.count();
  if (count >= 6) {
    for (let i = 0; i < 6; i++) {
      await multi.nth(i).fill(code[i]);
    }
  } else {
    const field = page.getByRole('textbox', { name: /验证码|code/i }).first();
    if (await field.count()) {
      await field.fill(code);
    } else {
      await page.locator('input').first().fill(code);
    }
  }
  const btn = page.getByRole('button', { name: /^(继续|Continue|Verify|提交|Submit)$/i }).first();
  if (await btn.count()) {
    await btn.click();
  }
}
JS
)"
    sleep 3
    continue
  fi

  if [[ "$PASSWORDINPUT" == "1" && -n "$OPENAI_PASSWORD" ]]; then
    run_code "$(cat <<JS
async (page) => {
  await page.locator('input[type=\"password\"], input[autocomplete=\"current-password\"], input[autocomplete=\"new-password\"]').first().fill("$PASSWORD_JS");
  const btn = page.getByRole('button', { name: /^(继续|Continue)$/i }).first();
  if (await btn.count()) {
    await btn.click();
  }
}
JS
)"
    sleep 2
    continue
  fi

  if [[ "$EMAILINPUT" == "1" ]]; then
    run_code "$(cat <<JS
async (page) => {
  const field = page.getByRole('textbox', { name: /电子邮件地址|email address|email/i }).first();
  if (await field.count()) {
    await field.fill("$EMAIL_JS");
  } else {
    await page.locator('input[type=\"email\"], input[autocomplete=\"email\"], input[name=\"email\"]').first().fill("$EMAIL_JS");
  }
  const btn = page.getByRole('button', { name: /^(继续|Continue|Next|下一步)$/i }).first();
  if (await btn.count()) {
    await btn.click();
    return;
  }
  throw new Error('continue button not found on codexbar email step');
}
JS
)"
    sleep 2
    continue
  fi

  if [[ "$AGEINPUT" == "1" || "$YEARINPUT" == "1" || "$NAMEINPUT" == "1" ]]; then
    run_code "$(cat <<JS
async (page) => {
  const fullName = "$ACCOUNT_NAME_JS";
  const age = "$AGE_JS";
  const year = "$BIRTH_YEAR_JS";
  const month = "$BIRTH_MONTH_JS";
  const day = "$BIRTH_DAY_JS";

  const fillFirstVisible = async (locators, value) => {
    for (const locator of locators) {
      if (await locator.count()) {
        const field = locator.first();
        if (await field.isVisible().catch(() => false)) {
          await field.fill(value);
          return true;
        }
      }
    }
    return false;
  };

  await fillFirstVisible([
    page.getByRole('textbox', { name: /全名|姓名|full name|name/i }),
    page.locator('input[autocomplete=\"name\"], input[name*=\"name\" i]')
  ], fullName);

  const ageFilled = await fillFirstVisible([
    page.getByRole('spinbutton', { name: /年龄|age/i }),
    page.locator('input[aria-label*=\"年龄\" i], input[name*=\"age\" i]')
  ], age);

  if (!ageFilled) {
    const yearSeg = page.getByRole('spinbutton', { name: /^年/i }).first();
    if (await yearSeg.count()) {
      await yearSeg.click();
      await page.keyboard.type(year + '/' + month + '/' + day);
      const hidden = page.locator('input[name=\"birthday\"]').first();
      if (await hidden.count()) {
        await hidden.evaluate((el, value) => {
          el.value = value;
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
        }, year + '-' + month + '-' + day);
      }
    }
  }

  const btn = page.getByRole('button', { name: /完成帐户创建|完成账户创建|create account|continue|继续/i }).first();
  if (await btn.count()) {
    await btn.click();
  }
}
JS
)"
    sleep 3
    continue
  fi

  sleep 2
done

if [[ "$status" != "IMPORTED" ]]; then
  if [[ "$stop_reason" == "phone_verification_required" ]]; then
    printf 'Codexbar import blocked by OpenAI phone verification for %s\n' "$OPENAI_EMAIL" >&2
  else
    printf 'timed out while importing %s into Codexbar\n' "$OPENAI_EMAIL" >&2
  fi
  exit 1
fi

printf 'IMPORTED_EMAIL=%s\n' "$OPENAI_EMAIL"
printf 'PLAYWRIGHT_SESSION=%s\n' "$SESSION"
python3 - <<'PY'
import json

with open('/Users/lzl/.codexbar/config.json', 'r', encoding='utf-8') as fh:
    config = json.load(fh)

active_provider = config.get("active", {}).get("providerId")
active_account = config.get("active", {}).get("accountId")
accounts = []

for provider in config.get("providers", []):
    if provider.get("kind") != "openai_oauth":
        continue
    for item in provider.get("accounts", []):
        accounts.append({
            "account_id": item.get("openAIAccountId") or item.get("id"),
            "email": item.get("email"),
            "active": provider.get("id") == active_provider and item.get("id") == active_account,
        })

print(json.dumps(accounts, ensure_ascii=False, indent=2))
PY
