---
name: utility-cf-deploy-token
description: 1Password のマスタートークンを使って Cloudflare のデプロイ用 API トークン (Workers Scripts + D1) を発行し、GitHub Actions の secrets に登録する。「デプロイ用のトークンを発行して」「Cloudflare のトークンを作って設定して」「CLOUDFLARE_API_TOKEN を用意して」「GitHub Actions から wrangler deploy できるようにして」などのリクエストで起動。既存トークンの権限変更・失効は対象外。
argument-hint: <プロジェクト名> [1Passwordの項目名]
allowed-tools: Bash, AskUserQuestion
---

# Cloudflare デプロイ用トークンの発行

1Password に保管したマスタートークン (トークン発行権限を持つもの) から、プロジェクト 1 つ分のスコープに絞ったデプロイ用トークンを発行し、GitHub Actions の secrets に登録する。

## 前提

- `op` が sign in 済み (`op whoami` で確認。未 sign in ならユーザに `op signin` を依頼して停止する)
- `gh` が対象リポジトリで認証済み (`gh repo view --json nameWithOwner` で確認)
- 1Password にマスタートークンの項目があること。既定の項目名は `Cloudflare Token` で、次の 2 フィールドを読む:
  - `credential` (CONCEALED) — トークン発行権限を持つマスタートークン
  - `account_id` — Cloudflare のアカウント ID

項目名やフィールド名が違う場合は `op item get '<項目名>' --format json | jq '[.fields[] | {id,label,type}]'` で構造を確かめてから読む (この出力に値は含まれない)。

## 秘密の扱い (厳守)

- **トークン値を標準出力に出さない**。`echo` / `jq` で値そのものを表示しない。長さ (`${#VAR}`) や成否だけを出す
- トークン値は環境変数か `chmod 600` の一時ファイルで運び、**使い終わったら必ず削除する**
- 一時ファイルはセッションのスクラッチディレクトリに置く (`/tmp` は使わない)
- **発行時のレスポンスにしか平文は現れない**。取り逃したら失効させて再発行する

**Bash 呼び出しをまたぐと環境変数は消える** (呼び出しごとにシェルが作り直され、cwd も戻る)。以下の各手順は 1 回の Bash 呼び出しで完結させ、`export` と `cd` はそのつど書き直す。手順をまたいで `$CF_MASTER` が残っている前提で書かないこと。

## 手順

### 1. マスタートークンの取得と疎通確認

```bash
export CF_MASTER="$(op item get 'Cloudflare Token' --fields label=credential --reveal)"
export CF_ACCOUNT="$(op item get 'Cloudflare Token' --fields label=account_id --reveal)"
echo "account_id length: ${#CF_ACCOUNT}, token length: ${#CF_MASTER}"
curl -s -H "Authorization: Bearer $CF_MASTER" \
  https://api.cloudflare.com/client/v4/user/tokens/verify | jq '{success, errors, status: .result.status}'
```

`success: true` かつ `status: "active"` でなければ、エラー内容を報告して停止する。

### 2. 付与する権限を決める

`wrangler deploy` と D1 マイグレーションに要るのは次の 3 つ。**アカウント単位** (`com.cloudflare.api.account`) の権限グループで、ID は Cloudflare 側で安定している。

| 権限グループ | ID | 用途 |
|---|---|---|
| Workers Scripts Write | `e086da7e2179491d91ee5f35b3ca210a` | `wrangler deploy` (Worker 本体と静的アセットのアップロード) |
| D1 Write | `09b2857d1c31407795e75e3fed8617a1` | `wrangler d1 migrations apply --remote` |
| Account Settings Read | `c1fde68c7bcc44588cbb6ddbc16d6480` | wrangler のアカウント解決 |

**R2 / KV の権限は入れない**。`wrangler deploy` はバインディングを宣言するだけでバケットや名前空間に触らないため。デプロイがそれで落ちたときに初めて `Workers R2 Storage Write` (`bf7481a1826f439697cb59a20b22293e`) 等を足す。

D1 を使わないプロジェクトなら D1 Write を外す。ID が通らなくなっていたら次で引き直す:

```bash
curl -s -H "Authorization: Bearer $CF_MASTER" \
  "https://api.cloudflare.com/client/v4/user/tokens/permission_groups?per_page=200" \
  | jq -r '.result[] | select(.scopes[]? == "com.cloudflare.api.account") | "\(.id)  \(.name)"' | sort -k2
```

### 3. 既存トークンとの重複確認

```bash
curl -s -H "Authorization: Bearer $CF_MASTER" \
  "https://api.cloudflare.com/client/v4/user/tokens?per_page=100" | jq -r '.result[] | "\(.status)  \(.name)"'
```

**命名は `<プロジェクト名>-deploy`** に揃える。同名が既にあれば、作り直すか流用するかをユーザに確認してから進む (勝手に失効させない)。

### 4. トークンの発行

有効期限は既定で付けない (CI が期限切れで突然止まらないようにするため)。ユーザが期限を望む場合は `expires_on` (RFC3339) を policies と同階層に足す。

```bash
SCRATCH="<スクラッチディレクトリ>/cf-token.txt"
RESP=$(curl -s -X POST -H "Authorization: Bearer $CF_MASTER" -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/user/tokens" \
  --data @<(jq -n --arg acct "$CF_ACCOUNT" --arg name "<プロジェクト名>-deploy" '{
    name: $name,
    policies: [{
      effect: "allow",
      resources: { ("com.cloudflare.api.account." + $acct): "*" },
      permission_groups: [
        { id: "e086da7e2179491d91ee5f35b3ca210a", name: "Workers Scripts Write" },
        { id: "09b2857d1c31407795e75e3fed8617a1", name: "D1 Write" },
        { id: "c1fde68c7bcc44588cbb6ddbc16d6480", name: "Account Settings Read" }
      ]
    }]
  }'))
echo "$RESP" | jq '{success, errors, name: .result.name, id: .result.id, status: .result.status, has_value: (.result.value | length > 0)}'
echo "$RESP" | jq -r '.result.value // empty' > "$SCRATCH"
chmod 600 "$SCRATCH"
```

`success: false` なら `errors` を報告して停止する (一時ファイルは削除する)。

### 5. 発行したトークンで実際に叩いて検証する

発行できたことと使えることは別なので、**そのトークン自身で**対象リソースに届くか確かめる。

```bash
export CF_NEW="$(cat "$SCRATCH")"
curl -s -H "Authorization: Bearer $CF_NEW" \
  https://api.cloudflare.com/client/v4/user/tokens/verify | jq '{success, status: .result.status}'
curl -s -H "Authorization: Bearer $CF_NEW" \
  "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/d1/database?name=<DB名>" \
  | jq '{success, dbs: [.result[]? | {name, uuid}]}'
curl -s -H "Authorization: Bearer $CF_NEW" \
  "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT/workers/scripts" \
  | jq '{success, errors: [.errors[]?.message]}'
```

D1 の `uuid` が `wrangler.jsonc` の `database_id` と一致することまで確認する。ずれていたら別のデータベースを指しているので、登録せずに報告して止まる。

### 6. 保管方針をユーザに確認する

**登録前に必ず AskUserQuestion で聞く** (秘密の複製先を勝手に増やさないため)。どれを選んでもトークン値は画面に出さない:

| 選択肢 | 行き先 |
|---|---|
| A: GitHub secrets のみ (既定) | 手順 7 → 8。控えは残さず、紛失したら再発行する |
| B: 1Password にも控えを残す | 下記で保存してから手順 7 → 8 |
| C: 登録しない | 一時ファイルのパスだけ伝え、ユーザが控えたと言ってから手順 8 |

B の保存:

```bash
op item create --category "API Credential" --title "<プロジェクト名>-deploy" \
  "credential[password]=$(cat "$SCRATCH")" "account_id[text]=$CF_ACCOUNT"
```

### 7. GitHub secrets への登録

```bash
REPO="<owner/repo>"
gh secret set CLOUDFLARE_API_TOKEN --repo "$REPO" < "$SCRATCH"
op item get 'Cloudflare Token' --fields label=account_id --reveal \
  | tr -d '\n' | gh secret set CLOUDFLARE_ACCOUNT_ID --repo "$REPO"
gh secret list --repo "$REPO"
```

`--repo` を明示する (cwd が対象リポジトリとは限らないため)。`account_id` は `tr -d '\n'` で改行を落とす。付いたまま入ると API 呼び出しが 400 になる。

### 8. 一時ファイルの削除

```bash
shred -u "$SCRATCH" 2>/dev/null || rm -P "$SCRATCH"
```

### 9. 報告

次を報告する:

- 発行したトークン名と付与した権限 (表で、各権限が何のために要るかを添える)
- 有効期限の扱い (既定は無期限。選んだ理由も書く)
- 検証結果 (verify / D1 の uuid 一致 / Workers への到達)
- `gh secret list` に 2 つ載ったこと
- 一時ファイルを削除したこと
- ユーザの次の操作 (push すると workflow が動く、など)

## 注意

- **マスタートークンを GitHub secrets に入れない**。CI に渡すのは発行したスコープ付きトークンだけ
- **失効はユーザの判断で行う**。不要に見える既存トークンを見つけても報告に留める (他プロジェクトの CI が使っている)
- 発行済みトークンの権限は後から変えられるが、値は変わらない。権限だけ直したいならトークンを作り直さず `PUT /user/tokens/<id>` を使う
- ローテーションするときは「新トークン発行 → secrets 更新 → workflow が green → 旧トークン失効」の順。先に失効させると CI が止まる
