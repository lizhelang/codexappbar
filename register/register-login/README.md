# Register & Login

分段执行 OpenAI 账号注册 + Codexbar 登录流程。

## 流程

```
01register  →  生成 iCloud 邮箱 → 注册 OpenAI  →  写入 codex.csv (status=registered)
02login     →  读取 codex.csv  →  登录 Codexbar  →  更新 status=success
```

## 用法

### 第一步：注册

```bash
# 默认注册 10 个
./01register

# 注册 50 个
./01register 50

# 注册 100 个，间隔 180 秒
COUNT=100 INTERVAL_SECS=180 ./01register
```

### 第二步：登录导入 Codexbar

```bash
# 登录所有 pending 的账号
./02login

# 只登录 20 个
./02login 20

# 登录 50 个，间隔 180 秒
COUNT=50 INTERVAL_SECS=180 ./02login

# 只处理指定邮箱
EMAIL_FILTER="xxx@icloud.com" ./02login 1
```

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `COUNT` | 注册/登录数量 | `10`（注册），全部 pending（登录） |
| `INTERVAL_SECS` | 每次操作间隔秒数 | `10`（注册），`150`（登录） |
| `CSV_PATH` | codex.csv 路径 | `../codex.csv` |
| `EMAIL_FILTER` | 仅处理指定邮箱（仅 02login） | 无 |

## 登录失败观测

- `02login` 和 `retry_codexbar_import_from_csv.sh` 会保留 CSV 状态为 `import_failed`
- 底层导入脚本会把失败样本写入 `~/.codexbar/register-import-observations.jsonl`
- 失败分类当前固定为：
  - `phone_verification`
  - `invalid_state`
  - `cdp_race`
  - `timeout`
- 汇总命令：

```bash
python3 ../scripts/summarize_import_observations.py
```

## CSV 状态流转

| status | 含义 |
|--------|------|
| `registered` | 注册成功，未导入 Codexbar |
| `success` | 已导入 Codexbar |
| `registration_failed` | 注册失败 |
| `import_failed` | 导入 Codexbar 失败（可重试） |
| `invalid` | 无效账号，跳过 |
