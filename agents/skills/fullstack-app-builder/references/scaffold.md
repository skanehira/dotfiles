# scaffold: テンプレートから新規プロジェクトを作る

- 種別: 手順書
- 対象: `fullstack-app-builder` スキルの本体 Step 3

`skanehira/fullstack-worker-template` は**プレースホルダ置換方式を採らず** `fullstack-worker-template` という具体名を直接埋め込んでいる (テンプレート自身の CI を green に保つため)。置換は同梱の `scripts/rename-project.sh` が行うが、**スクリプトが取りこぼす後始末が 4 つある** ので Step D で必ず手当てする。

## 目次

- Step A: テンプレートから clone
- Step B: rename-project.sh の実行
- Step C: 依存インストール
- Step D: rename の後始末 (4 箇所)
- Step E: D1 データベースの作成
- DoD
- よくある落とし穴

## Step A: テンプレートから clone

```bash
gh repo create <project-name> \
  --template skanehira/fullstack-worker-template \
  --private --clone
cd <project-name>
```

`--template` はテンプレートリポジトリ機能を使うため、`.git` 履歴を引き継がず新規リポジトリとして作られる。`<project-name>` は kebab-case (リポジトリ名・Worker 名・D1 データベース名の接頭辞になる)。

## Step B: rename-project.sh の実行

```bash
bash scripts/rename-project.sh <project-name>
```

スクリプトは `sed s/fullstack-worker-template/<project-name>/g` の**全文置換**を次の 4 ファイルに適用する:

| ファイル | 置換される箇所 |
| --- | --- |
| `package.json` | `"name"` |
| `wrangler.jsonc` | `"name"` / `d1_databases[0].database_name`。加えて `compatibility_date` を**実行日に上書きする** (これがローカル実行を壊すので Step D-3 で戻す) |
| `index.html` | `<title>` |
| `.github/workflows/deploy.yml` | `wrangler d1 migrations apply <db-name> --remote` の `<db-name>`。**併せてリポジトリ名ガードの `if:` 行も置換されてしまう** (Step D-1 で手当てする) |

## Step C: 依存インストール

```bash
vp install --frozen-lockfile
```

`postinstall` が `wrangler types` と `vp fmt worker-configuration.d.ts --write` を実行する。lefthook の `pre-push` フック (`vp check` + `vp build`) もここで設定される。

**`wrangler` は devDependency なのでグローバルには存在しない。** 以降 wrangler を使うときは必ず `vp exec wrangler ...` の形で呼ぶ (`vp exec` が `node_modules/.bin` のコマンドを実行する)。テンプレートの README / CLAUDE.md はベア表記になっているが、グローバルに wrangler を入れていない環境では動かない。

## Step D: rename の後始末 (4 箇所)

スクリプトは単純な全文置換のため以下が残る。**いずれも実測で確認済み**であり、放置すると開発サーバやデプロイが静かに壊れる。

### D-1. `deploy.yml` のリポジトリ名ガードを削除する

テンプレートの `deploy.yml` には、テンプレート自身では CD を走らせないためのガードがある:

```yaml
jobs:
  deploy:
    if: github.event.repository.name != 'fullstack-worker-template'
```

Step B の置換でこの行も `if: github.event.repository.name != '<project-name>'` になる。新プロジェクトのリポジトリ名は `<project-name>` なので条件が常に false となり、**deploy ジョブが恒久的にスキップされる** (CI は green なのにデプロイされない、という気付きにくい壊れ方をする)。

`.github/workflows/deploy.yml` から `if:` 行ごと削除する (新プロジェクトではガード自体が不要):

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
```

`terraform.yml` / `terraform-apply.yml` にも同じガードがあるが、こちらはスクリプトの置換対象外で `fullstack-worker-template` のまま残る。新プロジェクトのリポジトリ名とは一致しないため条件が真になり、正しく動作する。**この Step では触らない** (認証を使わない場合は Step 4 の customize でワークフローごと削除する)。

### D-2. `.github/workflows/deploy.yml.bak` を削除する

スクリプト末尾の `find . -maxdepth 2 -name "*.bak" -delete` は深さ 2 までしか掃かないため、`./.github/workflows/deploy.yml.bak` (深さ 3) が残る。

```bash
rm -f .github/workflows/deploy.yml.bak
```

### D-3. `compatibility_date` をテンプレートの初期値に戻す

スクリプトは `compatibility_date` を `date +%Y-%m-%d` (実行日) に書き換えるが、**この上書きはローカル実行を壊す**。ローカルランタイム (miniflare + workerd) が受け付ける日付には 2 段階の上限があり、実行日はどちらも超えうる:

| 判定する層 | 上限 | 超えたときのエラー |
| --- | --- | --- |
| miniflare (JS) | **UTC の今日** (`new Date().toISOString()` で判定) | `ERR_FUTURE_COMPATIBILITY_DATE: Compatibility date "..." is in the future and unsupported` |
| workerd (バイナリ) | **そのバイナリがサポートする最新日** (リリース日より数日先まで) | `ERR_RUNTIME_FAILURE` + `This Worker requires compatibility date "...", but the newest date supported by this server binary is "..."` |

`rename-project.sh` はローカルタイムの日付を入れるため、**JST (UTC+9) の 00:00〜08:59 に実行すると UTC ではまだ前日**で、1 段目に引っかかる。日中に実行しても、依存を更新していなければ 2 段目 (workerd の上限) に引っかかる。どちらの場合も `vp dev` も Worker テストも起動しない。

**clone 直後の値に戻すのが最も確実** (テンプレート自身の CI が green になっている日付なので、lockfile が pin する workerd と必ず整合する):

```bash
git show HEAD:wrangler.jsonc | rg -o '"compatibility_date": "([0-9-]+)"' -r '$1'
# → 出力された日付を wrangler.jsonc の compatibility_date に書き戻す
```

日付を新しく進めたい場合は、依存を更新 (`vp update` 等) したうえで Worker テストを実行し、`ERR_RUNTIME_FAILURE` のメッセージが示す "newest date supported by this server binary" 以下かつ UTC の今日以下に収める。**検証せずに日付だけ進めない。**

### D-4. テンプレート名が残るファイルを書き換える

以下はスクリプトの置換対象外なので、テンプレート名がそのまま残る:

- `src/front/pages/HomePage.tsx` — `<h1>Hello, fullstack-worker-template</h1>`
- `src/front/pages/HomePage.test.tsx` — 同じ文字列を `getByRole("heading", { name: ... })` で検証している (**片方だけ直すとテストが落ちる。必ず両方直す**)
- `README.md` — テンプレート自身の説明。プロジェクトの README に書き換える (最低限、タイトルと概要。セットアップ手順はテンプレートの記述が概ねそのまま使える)

HomePage の見出しはプロジェクト名にするなど、実装フェーズで UI を作り込むまでの仮表示でよい。

書き換えると文字列長が変わりフォーマッタの折り返し位置が動くため、**最後に `vp check --fix` を実行する** (これを忘れると `vp check` がフォーマット差分で落ちる。プロジェクト名がテンプレート名より短いと必ず起きる)。

## Step E: D1 データベースの作成

```bash
vp exec wrangler login          # 未ログインの場合のみ
vp exec wrangler d1 create <project-name>-db
```

出力される `database_id` を `wrangler.jsonc` の `d1_databases[0].database_id` に入れる (テンプレートの初期値は `"__D1_DATABASE_ID__"`)。

```jsonc
"d1_databases": [
  {
    "binding": "DB",
    "database_name": "<project-name>-db",
    "database_id": "実際の UUID",
  },
],
```

`__D1_DATABASE_ID__` のままでも `vp build` と CI は通るが、`wrangler deploy` はこの ID で対象データベースを解決するため本番投入前に必須。`database_id` は型に影響しないフィールドなので `wrangler types` の再生成は不要。

## DoD

```bash
# テンプレート名の残骸がない
# (terraform*.yml のガードと rename-project.sh 自身の OLD_NAME は意図的に残すので除外する)
rg -l --hidden 'fullstack-worker-template' \
  --glob '!node_modules' --glob '!pnpm-lock.yaml' \
  --glob '!scripts/rename-project.sh' \
  --glob '!.github/workflows/terraform*.yml' .        # 0 件

rg 'repository.name' .github/workflows/deploy.yml     # 0 件 (D-1)
find . -name '*.bak' -not -path './node_modules/*'    # 0 件 (D-2)
rg '__D1_DATABASE_ID__' wrangler.jsonc                # 0 件 (E)

# compatibility_date が clone 直後の値に戻っていること (D-3)
rg -o '"compatibility_date": "([0-9-]+)"' -r '$1' wrangler.jsonc
git show HEAD:wrangler.jsonc | rg -o '"compatibility_date": "([0-9-]+)"' -r '$1'   # 上と一致すること
```

D-3 の最終確認は Step 4 の Worker テスト (`vp exec vitest run -c vitest.workers.config.ts`) が green になることで取る。日付が不適切ならこのテストが起動時に落ちる。

`rg` は既定で hidden ディレクトリ (`.github/`) を検索しないため、`--hidden` を付けないと 1 番目のコマンドは残骸を見逃す。上記のとおり `--hidden` 付きで確認する。

二度目の rename は行わないので `scripts/rename-project.sh` は削除してもよい (残しても害はない)。

## よくある落とし穴

- **`vp dev` が起動しない / Worker テストが `ERR_FUTURE_COMPATIBILITY_DATE` または `ERR_RUNTIME_FAILURE` で落ちる** — Step D-3 未実施。`rename-project.sh` が `compatibility_date` を実行日に上書きしており、miniflare の UTC 判定か workerd バイナリのサポート上限を超えている。clone 直後の値に戻す
- **deploy が走らないのに CI は green** — Step D-1 のガード置換。`gh run list` に deploy の run は現れるがジョブが skipped になる
- **`vp check` が HomePage のテストで落ちる** — Step D-4 で `HomePage.tsx` だけ直して test を直し忘れた (テスト失敗)、または書き換え後に `vp check --fix` をかけ忘れた (フォーマット差分)
- **`wrangler: command not found`** — wrangler は devDependency。`vp exec wrangler ...` で呼ぶ。`vp install` より前には使えない
- **`vp exec wrangler d1 create` がアカウント選択を要求する** — 複数アカウントに所属している場合。`CLOUDFLARE_ACCOUNT_ID` を環境変数で渡すか、対話で選ぶ
- **`vp install` を `--frozen-lockfile` なしで実行してしまった** — Step C ではロックファイルを固定して CI と同条件にする。依存を変える Step 4 (customize) でのみ `--frozen-lockfile` を外す
