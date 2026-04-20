#!/usr/bin/env bash
# cf-issue-deploy-token.sh
#
# 新規プロジェクト向けに Cloudflare Workers デプロイ専用 API Token を発行し、
# 指定 GitHub リポジトリの Secrets に CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID を登録する。
#
# Usage:
#   curl -sSL <gist-raw-url> | bash -s -- [--dry-run] <project-name> [<github-repo>]
#   ./cf-issue-deploy-token.sh [--dry-run] <project-name> [<github-repo>]
#
# Flags:
#   --dry-run        副作用のある API を呼ばずに、依存・認証・参照・repo 解決まで検証
#
# Positional args:
#   <project-name>   Cloudflare の Worker 名。発行される token 名は "<project-name>-deploy"
#   <github-repo>    Secrets を登録する GitHub リポジトリ (owner/repo)。省略時は cwd の repo
#
# Env vars (overrideable):
#   CF_TOKEN_1P_REF     1Password の master token 参照 (default: op://Private/Cloudflare/credential)
#   CF_ACCOUNT_1P_REF   1Password の Account ID 参照   (default: op://Private/Cloudflare/account_id)
#
# Requires: curl, jq, op (1Password CLI), gh (GitHub CLI)

set -euo pipefail

# ---------- 設定 ----------
TOKEN_REF="${CF_TOKEN_1P_REF:-op://Private/Cloudflare/credential}"
ACCOUNT_REF="${CF_ACCOUNT_1P_REF:-op://Private/Cloudflare/account_id}"
WORKERS_WRITE_PG="e086da7e2179491d91ee5f35b3ca210a"   # "Workers Scripts Write"

DRY_RUN=0
POSITIONAL=()

while (( $# > 0 )); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --) shift; POSITIONAL+=("$@"); break ;;
    -*) echo "error: unknown flag: $1" >&2; exit 1 ;;
    *)  POSITIONAL+=("$1"); shift ;;
  esac
done

PROJECT_NAME="${POSITIONAL[0]:-}"
TARGET_REPO="${POSITIONAL[1]:-}"

if [[ -z "$PROJECT_NAME" ]]; then
  cat <<USAGE >&2
usage: $0 [--dry-run] <project-name> [<github-repo>]

  <project-name>  Cloudflare Worker 名 (token 名は "<project-name>-deploy")
  <github-repo>   GitHub リポジトリ owner/repo 形式。省略時は cwd の repo

env:
  CF_TOKEN_1P_REF    (default: $TOKEN_REF)
  CF_ACCOUNT_1P_REF  (default: $ACCOUNT_REF)
USAGE
  exit 1
fi

log() { printf '▸ %s\n' "$*"; }
ok()  { printf '✓ %s\n' "$*"; }

# ---------- 依存チェック ----------
log "依存コマンドを確認..."
missing=()
for cmd in curl jq op gh; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if (( ${#missing[@]} > 0 )); then
  printf 'error: missing commands: %s\n' "${missing[*]}" >&2
  exit 1
fi
ok "curl / jq / op / gh 確認"

# ---------- gh 認証確認 ----------
log "GitHub CLI のサインインを確認..."
if ! gh auth status >/dev/null 2>&1; then
  echo "error: gh にログインしてください (gh auth login)" >&2
  exit 1
fi
ok "gh auth OK"

# ---------- GitHub repo の解決 ----------
if [[ -z "$TARGET_REPO" ]]; then
  if ! TARGET_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"; then
    echo "error: specify <github-repo> or run inside a GitHub repo clone" >&2
    exit 1
  fi
fi
ok "GitHub repo: $TARGET_REPO"

# repo がアクセス可能か
if ! gh repo view "$TARGET_REPO" --json nameWithOwner >/dev/null 2>&1; then
  echo "error: $TARGET_REPO にアクセスできません" >&2
  exit 1
fi

# ---------- 1Password から credentials 取得 ----------
log "1Password から credentials を取得..."
if ! MASTER_TOKEN="$(op read "$TOKEN_REF" 2>/dev/null)" || [[ -z "$MASTER_TOKEN" ]]; then
  cat <<MSG >&2
error: op read "$TOKEN_REF" に失敗しました。
  - 1Password デスクトップアプリのロックが解除されているか？
  - 複数アカウント環境なら 'op account list' で対象を確認し
    eval "\$(op signin --account my)" 等で明示的にサインインを
MSG
  exit 1
fi
if ! ACCOUNT_ID="$(op read "$ACCOUNT_REF" 2>/dev/null)" || [[ -z "$ACCOUNT_ID" ]]; then
  echo "error: op read \"$ACCOUNT_REF\" に失敗しました" >&2
  exit 1
fi
ok "op read 成功 (account_id 下4桁: ...${ACCOUNT_ID: -4})"

TOKEN_NAME="${PROJECT_NAME}-deploy"

# ---------- dry-run はここで抜ける ----------
if (( DRY_RUN == 1 )); then
  cat <<DRY
────────────── DRY RUN SUMMARY ──────────────
 project     : $PROJECT_NAME
 target repo : $TARGET_REPO
 token name  : $TOKEN_NAME
 CF endpoint : POST https://api.cloudflare.com/client/v4/user/tokens
 permissions : Workers Scripts Write
 scope       : com.cloudflare.api.account.<your-account-id>
 gh secrets  : CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID
─────────────────────────────────────────────
本番実行するには --dry-run を外してください。
DRY
  exit 0
fi

# ---------- Cloudflare API で token 発行 ----------
log "Cloudflare API で token を発行..."
PAYLOAD="$(jq -n \
  --arg name "$TOKEN_NAME" \
  --arg acct "$ACCOUNT_ID" \
  --arg pgid "$WORKERS_WRITE_PG" \
  '{
     name: $name,
     policies: [{
       effect: "allow",
       resources: { ("com.cloudflare.api.account." + $acct): "*" },
       permission_groups: [{ id: $pgid }]
     }]
   }')"

RESPONSE="$(curl -sS https://api.cloudflare.com/client/v4/user/tokens \
  -H "Authorization: Bearer $MASTER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")"

if ! printf '%s' "$RESPONSE" | jq -e '.success' >/dev/null; then
  echo "error: Cloudflare API failed" >&2
  printf '%s' "$RESPONSE" | jq '.errors // .' >&2
  exit 1
fi

NEW_TOKEN="$(printf '%s' "$RESPONSE" | jq -r '.result.value')"
TOKEN_ID="$(printf '%s' "$RESPONSE" | jq -r '.result.id')"

if [[ -z "$NEW_TOKEN" || "$NEW_TOKEN" == "null" ]]; then
  echo "error: response did not include token value" >&2
  exit 1
fi

ok "token 発行 (id: $TOKEN_ID, name: $TOKEN_NAME)"

# ---------- GitHub Secrets に登録 ----------
log "GitHub Secrets に登録..."
printf '%s' "$NEW_TOKEN"  | gh secret set CLOUDFLARE_API_TOKEN  --repo "$TARGET_REPO"
printf '%s' "$ACCOUNT_ID" | gh secret set CLOUDFLARE_ACCOUNT_ID --repo "$TARGET_REPO"
ok "$TARGET_REPO に CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID を登録"

echo
echo "完了。次のステップ："
echo "  1. git push（GitHub Actions が自動でデプロイ）"
echo "  2. または 手元で 'pnpm run deploy' を実行"
