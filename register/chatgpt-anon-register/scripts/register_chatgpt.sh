#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODE_SCRIPT="$ROOT_DIR/scripts/get_latest_openai_code.applescript"
SESSION_RAW="${PLAYWRIGHT_SESSION:-cg$(date +%H%M%S)}"
ACCOUNT_NAME="${ACCOUNT_NAME:-River Vale}"
BIRTH_YEAR="${BIRTH_YEAR:-1990}"
BIRTH_MONTH="${BIRTH_MONTH:-01}"
BIRTH_DAY="${BIRTH_DAY:-08}"
AGE="${AGE:-}"
RELAY_EMAIL="${RELAY_EMAIL:-}"
PASSWORD="${PASSWORD:-}"
KEEP_PLAYWRIGHT_SESSION="${KEEP_PLAYWRIGHT_SESSION:-0}"
PREFER_EMAIL_OTP="${PREFER_EMAIL_OTP:-1}"
STOP_AFTER_EMAIL_VERIFICATION="${STOP_AFTER_EMAIL_VERIFICATION:-1}"

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
    clean="cg$(date +%H%M%S)"
  fi
  printf '%s\n' "$clean"
}

extract_eval_json() {
  python3 -c '
import json
import re
import sys

text = sys.stdin.read()
match = re.search(r"### Result\s*(.*?)\s*### Ran Playwright code", text, re.S)
if not match:
    sys.stderr.write(text)
    raise SystemExit(1)

payload = match.group(1).strip()
try:
    decoded = json.loads(payload)
except json.JSONDecodeError:
    sys.stderr.write(text)
    raise

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

SESSION="$(sanitize_session "$SESSION_RAW")"

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

sleep_brief() {
  sleep "${1:-1}"
}

current_state_json() {
  eval_json "$(cat <<'JS'
() => JSON.stringify((() => {
  const bodyText = (document.body?.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 6000);
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

  const visibleInputs = visible('input, textarea');
  const emailInput = visibleInputs.some((el) => el.matches('input[type="email"], input[autocomplete="email"]') || /email|电子邮件|邮箱/.test(attrs(el)));
  const passwordInput = visibleInputs.some((el) => el.matches('input[type="password"]') || /password|密码/.test(attrs(el)));
  const codeInput = visibleInputs.some((el) => el.matches('input[autocomplete="one-time-code"]') || /code|验证码/.test(attrs(el)) || String(el.maxLength) === '6' || String(el.maxLength) === '1');
  const phoneInput = visibleInputs.some((el) => el.matches('input[type="tel"], input[autocomplete="tel"]') || /phone|手机|电话/.test(attrs(el)));
  const nameInput = visibleInputs.some((el) => /full name|name|全名|姓名/.test(attrs(el)));
  const ageInput = visibleInputs.some((el) => /年龄|(^|[^a-z])age([^a-z]|$)/.test(attrs(el)));
  const yearInput = visibleInputs.some((el) => !/年龄|(^|[^a-z])age([^a-z]|$)/.test(attrs(el)) && /year|出生年|年份/.test(attrs(el)));
  const monthInput = visibleInputs.some((el) => /month|月/.test(attrs(el)));
  const dayInput = visibleInputs.some((el) => /day|日/.test(attrs(el)));
  const promptTextarea = visible('#prompt-textarea, textarea[data-id], textarea[placeholder*="Message" i], textarea[placeholder*="消息" i], textarea[placeholder*="向 ChatGPT" i]').length > 0;
  const moreOptions = /更多选项|more options/.test(lowered);
  const signupEntry = /sign up|signup|create account|注册|创建帐户|创建账户/.test(lowered);
  const resendButton = /resend email|resend|send again|重新发送电子邮件|重新发送/.test(lowered);
  const otpRegistrationOption = /使用一次性验证码注册|one-time passcode|one-time code|email code/i.test(lowered);
  const captchaChallenge = /captcha|verify you are human|robot|真人验证|人机验证/.test(lowered);
  const phoneChallenge = (
    !emailInput &&
    !passwordInput &&
    !codeInput &&
    !/accounts\.google\.com|appleid|microsoft/i.test(location.href) &&
    (/verify your phone|phone verification|enter your phone|phone number|手机号验证|验证你的手机|手机号码/.test(lowered) ||
     (/短信/.test(lowered) && /手机号|手机号码|电话/.test(lowered)))
  );
  const success = (
    location.href.startsWith('https://chatgpt.com/') &&
    !/auth\.openai\.com|\/log-in|\/password|email-verification|phone|captcha/i.test(location.href) &&
    (promptTextarea || /what can i help with|how can i help|给 chatgpt 发送消息|新建聊天|temporary chat|message chatgpt/i.test(lowered))
  );

  return {
    href: location.href,
    title: document.title,
    bodyText,
    emailInput,
    passwordInput,
    codeInput,
    phoneInput,
    nameInput,
    ageInput,
    yearInput,
    monthInput,
    dayInput,
    promptTextarea,
    moreOptions,
    signupEntry,
    resendButton,
    otpRegistrationOption,
    captchaChallenge,
    phoneChallenge,
    success
  };
})())
JS
)"
}

latest_code() {
  osascript "$CODE_SCRIPT" 2>/dev/null | tr -d '\r\n'
}

cleanup_playwright() {
  if [[ "$KEEP_PLAYWRIGHT_SESSION" == "1" ]]; then
    return
  fi
  playwright-cli session-stop "$SESSION" >/dev/null 2>&1 || true
  playwright-cli session-delete "$SESSION" >/dev/null 2>&1 || true
}

trap cleanup_playwright EXIT

if [[ -z "$RELAY_EMAIL" ]]; then
  printf 'usage: RELAY_EMAIL=<fresh_relay@icloud.com> %s\n' "$0" >&2
  exit 64
fi

require_cmd playwright-cli
require_cmd osascript
require_cmd openssl
require_cmd python3

if [[ -z "$PASSWORD" ]]; then
  PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)"
fi

EMAIL_JS="${RELAY_EMAIL//\\/\\\\}"
EMAIL_JS="${EMAIL_JS//\"/\\\"}"
PASSWORD_JS="${PASSWORD//\\/\\\\}"
PASSWORD_JS="${PASSWORD_JS//\"/\\\"}"
NAME_JS="${ACCOUNT_NAME//\\/\\\\}"
NAME_JS="${NAME_JS//\"/\\\"}"
YEAR_JS="${BIRTH_YEAR//\\/\\\\}"
YEAR_JS="${YEAR_JS//\"/\\\"}"
MONTH_JS="${BIRTH_MONTH//\\/\\\\}"
MONTH_JS="${MONTH_JS//\"/\\\"}"
DAY_JS="${BIRTH_DAY//\\/\\\\}"
DAY_JS="${DAY_JS//\"/\\\"}"
if [[ -z "$AGE" && "$BIRTH_YEAR" =~ ^[0-9]{4}$ ]]; then
  AGE="$(( $(date +%Y) - BIRTH_YEAR ))"
fi
AGE_JS="${AGE//\\/\\\\}"
AGE_JS="${AGE_JS//\"/\\\"}"

playwright-cli session-stop "$SESSION" >/dev/null 2>&1 || true
playwright-cli session-delete "$SESSION" >/dev/null 2>&1 || true
pw --isolated --browser chrome --headed open about:blank >/dev/null

run_code "$(cat <<'JS'
async (page) => {
  await page.waitForLoadState('domcontentloaded');
  await page.goto('https://chatgpt.com/auth/login', { waitUntil: 'domcontentloaded' });
}
JS
)"

signup_attempts=0
email_attempts=0
password_attempts=0
code_attempts=0
resend_attempts=0
profile_attempts=0
used_email_otp=0
mail_code_baseline="$(latest_code || true)"

status="IN_PROGRESS"
stop_reason=""
deadline=$((SECONDS + 300))

while (( SECONDS < deadline )); do
  STATE_JSON="$(current_state_json)"
  load_state_vars "$STATE_JSON"

  if [[ "$STOP_AFTER_EMAIL_VERIFICATION" == "1" && "$code_attempts" -gt 0 && "$CODEINPUT" == "0" && "$HREF" != *"email-verification"* ]]; then
    status="REGISTERED_AFTER_EMAIL_VERIFICATION"
    stop_reason="email_verification_complete"
    break
  fi

  if [[ "$SUCCESS" == "1" ]]; then
    status="REGISTERED"
    break
  fi

  if [[ "$CAPTCHACHALLENGE" == "1" ]]; then
    printf 'captcha challenge detected during registration\n' >&2
    exit 1
  fi

  if [[ "$PHONECHALLENGE" == "1" ]]; then
    status="PHONE_VERIFICATION_REQUIRED"
    stop_reason="phone_verification"
    pw close >/dev/null 2>&1 || true
    break
  fi

  if [[ "$PASSWORDINPUT" == "1" ]]; then
    ((password_attempts += 1))
    run_code "$(cat <<JS
async (page) => {
  const password = "$PASSWORD_JS";
  const fields = [
    page.getByRole('textbox', { name: /密码|password/i }),
    page.locator('input[type=\"password\"]')
  ];
  for (const locator of fields) {
    if (await locator.count()) {
      const field = locator.first();
      if (await field.isVisible().catch(() => false)) {
        await field.fill(password);
        break;
      }
    }
  }
  const buttons = [
    page.getByRole('button', { name: /^(继续|Continue|Next|下一步)$/i }),
    page.locator('form button[type=\"submit\"], form button')
  ];
  for (const locator of buttons) {
    if (await locator.count()) {
      const button = locator.first();
      const label = ((await button.textContent().catch(() => '')) || '').toLowerCase();
      if (await button.isVisible().catch(() => false) && (/^(继续|continue|next|下一步)$/.test(label.trim()) || locator === buttons[1])) {
        await button.click();
        return;
      }
    }
  }
  throw new Error('continue button not found on password step');
}
JS
)"
    sleep_brief 2
    continue
  fi

  if [[ "$EMAILINPUT" == "1" ]]; then
    ((email_attempts += 1))
    run_code "$(cat <<JS
async (page) => {
  const email = "$EMAIL_JS";
  const candidates = [
    page.getByRole('textbox', { name: /电子邮件地址|email address|email/i }),
    page.locator('input[type=\"email\"], input[autocomplete=\"email\"], input[name=\"email\"]')
  ];
  for (const locator of candidates) {
    if (await locator.count()) {
      const field = locator.first();
      if (await field.isVisible().catch(() => false)) {
        await field.fill(email);
        break;
      }
    }
  }
  const buttons = [
    page.getByRole('button', { name: /^(继续|Continue|Next|下一步)$/i }),
    page.getByRole('link', { name: /^(继续|Continue|Next|下一步)$/i }),
    page.locator('form button[type=\"submit\"], form button')
  ];
  for (const locator of buttons) {
    if (await locator.count()) {
      const button = locator.first();
      const label = ((await button.textContent().catch(() => '')) || '').toLowerCase();
      if (await button.isVisible().catch(() => false) && (/^(继续|continue|next|下一步)$/.test(label.trim()) || locator === buttons[2])) {
        await button.click();
        return;
      }
    }
  }
  throw new Error('continue button not found on email step');
}
JS
)"
    sleep_brief 2
    continue
  fi

  if [[ "$CODEINPUT" == "1" ]]; then
    if (( code_attempts > 0 && resend_attempts < 2 )); then
      ((resend_attempts += 1))
      run_code "$(cat <<'JS'
async (page) => {
  const buttons = [
    page.getByRole('button', { name: /重新发送电子邮件|重新发送|resend email|resend|send again/i }),
    page.getByRole('link', { name: /重新发送电子邮件|重新发送|resend email|resend|send again/i }),
    page.locator('button, a')
  ];
  for (const locator of buttons) {
    if (await locator.count()) {
      const button = locator.first();
      const label = ((await button.textContent().catch(() => '')) || '').toLowerCase();
      if (await button.isVisible().catch(() => false) && /重新发送|resend|send again/.test(label)) {
        await button.click();
        return;
      }
    }
  }
}
JS
)"
      sleep_brief 5
    else
      sleep_brief 5
    fi

    CODE="$(latest_code || true)"
    if [[ ! "$CODE" =~ ^[0-9]{6}$ || ( -n "$mail_code_baseline" && "$CODE" == "$mail_code_baseline" ) ]]; then
      sleep_brief 2
      continue
    fi

    ((code_attempts += 1))
    mail_code_baseline="$CODE"
    CODE_JS="${CODE//\\/\\\\}"
    CODE_JS="${CODE_JS//\"/\\\"}"

    run_code "$(cat <<JS
async (page) => {
  const code = "$CODE_JS";
  const multiFields = page.locator('input[autocomplete=\"one-time-code\"], input[inputmode=\"numeric\"], input[maxlength=\"1\"]');
  const multiCount = await multiFields.count();
  if (multiCount >= 6) {
    for (let i = 0; i < 6; i++) {
      await multiFields.nth(i).fill(code[i]);
    }
  } else {
    const candidates = [
      page.getByRole('textbox', { name: /验证码|code/i }),
      page.locator('input[autocomplete=\"one-time-code\"], input[inputmode=\"numeric\"], input[maxlength=\"6\"], input')
    ];
    for (const locator of candidates) {
      if (await locator.count()) {
        const field = locator.first();
        if (await field.isVisible().catch(() => false)) {
          await field.fill(code);
          break;
        }
      }
    }
  }
  const buttons = [
    page.getByRole('button', { name: /^(继续|Continue|Verify|提交|Submit)$/i }),
    page.locator('form button[type=\"submit\"], form button')
  ];
  for (const locator of buttons) {
    if (await locator.count()) {
      const button = locator.first();
      const label = ((await button.textContent().catch(() => '')) || '').toLowerCase();
      if (await button.isVisible().catch(() => false) && (/^(继续|continue|verify|submit|提交)$/.test(label.trim()) || locator === buttons[1])) {
        await button.click();
        return;
      }
    }
  }
}
JS
)"
    sleep_brief 3
    continue
  fi

  if [[ "$MOREOPTIONS" == "1" && "$EMAILINPUT" == "0" ]]; then
    run_code "$(cat <<'JS'
async (page) => {
  const buttons = [
    page.getByRole('button', { name: /更多选项|more options/i }),
    page.locator('button')
  ];
  for (const locator of buttons) {
    if (await locator.count()) {
      const button = locator.first();
      const label = ((await button.textContent().catch(() => '')) || '').toLowerCase();
      if (await button.isVisible().catch(() => false) && /更多选项|more options/.test(label)) {
        await button.click();
        return;
      }
    }
  }
  throw new Error('more options button not found');
}
JS
)"
    sleep_brief 1
    continue
  fi

  if [[ "$PREFER_EMAIL_OTP" == "1" && "$OTPREGISTRATIONOPTION" == "1" ]]; then
    used_email_otp=1
    run_code "$(cat <<'JS'
async (page) => {
  const buttons = [
    page.getByRole('button', { name: /使用一次性验证码注册|one-time passcode|one-time code|email code/i }),
    page.getByRole('link', { name: /使用一次性验证码注册|one-time passcode|one-time code|email code/i }),
    page.locator('button, a')
  ];
  for (const locator of buttons) {
    if (await locator.count()) {
      const button = locator.first();
      const label = ((await button.textContent().catch(() => '')) || '').toLowerCase();
      if (await button.isVisible().catch(() => false) && /使用一次性验证码注册|one-time passcode|one-time code|email code/.test(label)) {
        await button.click();
        return;
      }
    }
  }
  throw new Error('one-time code registration option not found');
}
JS
)"
    sleep_brief 2
    continue
  fi

  if [[ "$NAMEINPUT" == "1" || "$AGEINPUT" == "1" || ( "$YEARINPUT" == "1" && "$MONTHINPUT" == "1" && "$DAYINPUT" == "1" ) ]]; then
    ((profile_attempts += 1))
    run_code "$(cat <<JS
async (page) => {
  const fullName = "$NAME_JS";
  const age = "$AGE_JS";
  const year = "$YEAR_JS";
  const month = "$MONTH_JS";
  const day = "$DAY_JS";
  const birthdayDisplay = `${year}/${month}/${day}`;

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
    const yearSegment = page.getByRole('spinbutton', { name: /^年/i });
    let dateSegmentsFilled = false;
    if (await yearSegment.count() && await yearSegment.first().isVisible().catch(() => false)) {
      await yearSegment.first().click();
      await yearSegment.first().press('Meta+A').catch(() => {});
      for (let i = 0; i < 8; i++) {
        await page.keyboard.press('Backspace').catch(() => {});
      }
      await page.keyboard.type(birthdayDisplay);
      dateSegmentsFilled = true;
    }

    if (!dateSegmentsFilled) {
      await fillFirstVisible([
        page.getByRole('spinbutton', { name: /年|year/i }),
        page.locator('input[aria-label*=\"年\" i], input[name*=\"year\" i]')
      ], year);

      await fillFirstVisible([
        page.getByRole('spinbutton', { name: /月|month/i }),
        page.locator('input[aria-label*=\"月\" i], input[name*=\"month\" i]')
      ], month);

      await fillFirstVisible([
        page.getByRole('spinbutton', { name: /日|day/i }),
        page.locator('input[aria-label*=\"日\" i], input[name*=\"day\" i]')
      ], day);
    }

    const birthdayHidden = page.locator('input[name=\"birthday\"]');
    if (await birthdayHidden.count()) {
      await birthdayHidden.evaluate((el, value) => {
        el.value = value;
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      }, `${year}-${month}-${day}`);
    }
  }

  const buttons = [
    page.getByRole('button', { name: /完成帐户创建|完成账户创建|complete account creation|create account|continue/i }),
    page.locator('form button[type=\"submit\"], form button')
  ];
  for (const locator of buttons) {
    if (await locator.count()) {
      const button = locator.first();
      const label = ((await button.textContent().catch(() => '')) || '').toLowerCase();
      if (await button.isVisible().catch(() => false) && (/完成|create account|continue|提交|submit/.test(label) || locator === buttons[1])) {
        await button.click();
        return;
      }
    }
  }
}
JS
)"
    sleep_brief 3
    continue
  fi

  if [[ "$SIGNUPENTRY" == "1" && "$EMAILINPUT" == "0" ]]; then
    ((signup_attempts += 1))
    run_code "$(cat <<'JS'
async (page) => {
  const candidates = [
    page.getByRole('button', { name: /免费注册|sign up|create account/i }),
    page.getByRole('link', { name: /免费注册|sign up|create account/i }),
    page.getByTestId('signup-button')
  ];
  for (const locator of candidates) {
    if (await locator.count()) {
      const button = locator.first();
      const label = ((await button.textContent().catch(() => '')) || '').toLowerCase();
      if (await button.isVisible().catch(() => false) && /免费注册|sign up|signup|create account/.test(label || 'sign up')) {
        await button.click();
        return;
      }
    }
  }
  throw new Error('free signup entry not found on chatgpt login page');
}
JS
)"
    sleep_brief 2
    continue
  fi

  sleep_brief 2
done

if [[ "$status" == "IN_PROGRESS" ]]; then
  printf 'timed out while registering %s on chatgpt.com\n' "$RELAY_EMAIL" >&2
  exit 1
fi

printf 'REGISTERED_EMAIL=%s\n' "$RELAY_EMAIL"
if [[ "$used_email_otp" == "1" ]]; then
  printf 'PASSWORD=\n'
else
  printf 'PASSWORD=%s\n' "$PASSWORD"
fi
printf 'PLAYWRIGHT_SESSION=%s\n' "$SESSION"
printf 'REGISTRATION_STATUS=%s\n' "$status"
printf 'AUTH_METHOD=%s\n' "$([[ "$used_email_otp" == "1" ]] && printf 'email_otp' || printf 'password')"
if [[ -n "$stop_reason" ]]; then
  printf 'STOP_REASON=%s\n' "$stop_reason"
fi
