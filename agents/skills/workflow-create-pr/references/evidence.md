# 動作確認の証跡を集める

- 種別: 手順書
- 読み手: 証跡を集める側。dev-impl では `dev-impl-implementer` が読む。手動で PR を作る人が証跡を用意するときも同じ手順に従う
- 消費者: `workflow-create-pr` が `--evidence <manifest.json>` で受け取り、PR 本文の「動作確認」節に埋め込んで、画像を `gh pr create --attach` で添付する

PR を読む人が、画面が実際にどう変わったかと、API が実際に何を返したかを本文から追えるようにする。画面はスクリーンショットを操作の順に並べ、API は実行したリクエストと実際のレスポンスをテキストで残す。動画は撮らない。

## 置き場所とマニフェスト

証跡は呼び出し側が渡す `evidence_dir` (絶対パス。dev-impl では `<SCRATCH>/evidence-<N>`) の下にだけ置く。リポジトリの中には置かない (コミットに混ざるため)。

```text
<evidence_dir>/
├── manifest.json        ← workflow-create-pr が読む唯一の入口
├── screens/
│   ├── screens.ndjson   ← ヘルパー capture が 1 枚ごとに 1 行追記する
│   ├── 01-<slug>.png
│   └── 02-<slug>.png
└── api/
    ├── 01-<slug>.txt
    └── 02-<slug>.txt
```

取り直すときは `evidence_dir` の中身を全部消してから撮る。消さずに撮り直すと、前回より状態が減ったときに古い画像が残り、PR に今の実装と違う画面が載る。

`manifest.json` は画面も API も無い issue でも必ず書く。そのときは両方を空配列にして、`note` に理由を書く (例: `cli モードの issue で、画面と HTTP API の変更が無い`)。空のマニフェストがあれば「撮らなかった」ではなく「該当しない」と読める。

```json
{
  "issue": 12,
  "captured_mode": "implement",
  "screens": [
    { "flow": "（US-003）会員がメールアドレスを入力して登録すると、確認メールの案内が出る", "step": 1, "state": "会員登録画面 (初期表示)", "file": "/abs/evidence-12/screens/01-screen.png", "width": 1280 },
    { "flow": "（US-003）会員がメールアドレスを入力して登録すると、確認メールの案内が出る", "step": 2, "state": "登録ボタンを押した後 (確認メールの案内)", "file": "/abs/evidence-12/screens/02-screen.png", "width": 1280 }
  ],
  "api": [
    { "case": "POST /api/members — 成功", "file": "/abs/evidence-12/api/01-post-members-ok.txt" },
    { "case": "POST /api/members — メールアドレスの形式が誤り", "file": "/abs/evidence-12/api/02-post-members-invalid-email.txt" }
  ],
  "note": ""
}
```

| キー | 中身 |
| --- | --- |
| `issue` | issue 番号。手動で用意したときは `0` |
| `captured_mode` | 撮った時点の実装者の起動モード (`implement` / `fix`)。dev-impl の親が「最後に done になった報告の証跡か」を照合する |
| `screens[].flow` | 機能設計書の `E2E 対象動線:` 行をそのまま写す |
| `screens[].step` / `state` / `file` / `width` | `screens.ndjson` の 1 行をそのまま写す。`state` は画面に何が出ているかを利用者の言葉で書く |
| `api[].case` | `<METHOD> <path> — <ケース名>`。ケース名は入力の条件を書く (例: `メールアドレスの形式が誤り`) |
| `api[].file` | 下の「API」の書式で書いたファイルの絶対パス |
| `note` | 両方が空のときの理由と、動線外の変更の注記。無ければ空文字 |

`file` は全て絶対パスで書き、書いたファイルが実在することを `ls` で確かめる。実在しないパスが残ると `gh pr create --attach` が失敗する。

## 画面

### 何を撮るか

状態遷移が読み取れるように、golden path の E2E を進めながら次の時点で撮る。1 枚ずつではなく、操作の前後が並ぶことで「何をしたら何が出たか」が伝わる。

1. 動線が通る各画面の初期表示
2. 利用者の操作で表示が変わった直後 (送信した後・遷移した後・エラーが出た後)
3. 動線の終端

撮るのは表示が落ち着いてからにする。E2E のアサーション (`await expect(...).toBeVisible()` など) を通った直後に撮れば、読み込み中の画面が写らない。

viewport は 1 つの幅に固定し、`fullPage` は使わない。幅を変えた見た目の確認は視覚テストの役目で、E2E の証跡では幅を振らない。

### 撮れないもの

スクリーンショットは golden path の E2E からだけ撮る。今回の変更が golden path の上に現れない場合 (補助画面・動線が通らないエラー表示など) は、証跡のために E2E を増やさない。マニフェストの `note` に `動線外の変更: <画面名・状態>。見た目は視覚テストで確認` と書く。

### ヘルパー

E2E のディレクトリに次のヘルパーを置き、golden path の spec から呼ぶ。最初に UI を実装する issue が作り、以後の issue は再利用する。置き場所は `docs/design/DESIGN.md`「開発・検証コマンド」が示す E2E のディレクトリに合わせる (例: `e2e/evidence.ts`)。

```ts
import { appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import type { Page } from "@playwright/test";

const evidenceDir = process.env.E2E_EVIDENCE_DIR;
let step = 0;

export async function capture(page: Page, state: string): Promise<void> {
  // 環境変数が無い実行 (検証・レビュー・CI) で書き出すと、他の spec の画像が混ざり、リポジトリにも残るため何もしない
  if (!evidenceDir) return;
  step += 1;
  mkdirSync(evidenceDir, { recursive: true });
  const slug = state.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "screen";
  const file = join(evidenceDir, `${String(step).padStart(2, "0")}-${slug}.png`);
  await page.screenshot({ path: file, fullPage: false });
  appendFileSync(
    join(evidenceDir, "screens.ndjson"),
    `${JSON.stringify({ step, state, file, width: page.viewportSize()?.width ?? 0 })}\n`,
  );
}
```

番号はモジュールの中の 1 つのカウンタで振る。golden path を 1 本の `test()` で書くのはこのためで、`test()` を分けると並列実行で番号が混ざる。ファイル名の slug は英数字だけを使う (日本語の状態名は `screen` になる)。日本語や括弧をファイル名に入れると、PR 本文の画像参照が壊れることがある。

```ts
test("会員登録の golden path", async ({ page }) => {
  await page.goto("/signup");
  await expect(page.getByRole("heading", { name: "会員登録" })).toBeVisible();
  await capture(page, "会員登録画面 (初期表示)");

  await page.getByLabel("メールアドレス").fill("member@example.com");
  await page.getByRole("button", { name: "登録" }).click();
  await expect(page.getByText("確認メールを送りました")).toBeVisible();
  await capture(page, "登録ボタンを押した後 (確認メールの案内)");
});
```

### 撮る手順

1. `evidence_dir` の中身を消す
2. golden path の spec だけを、環境変数を付けて実行する。リトライで同じ状態が二重に撮られないよう、リトライは 0 回にする

   ```bash
   cd <repo_dir> && E2E_EVIDENCE_DIR=<evidence_dir>/screens npx playwright test <golden path の spec> --retries=0
   ```

   コマンドの形は `docs/design/DESIGN.md`「開発・検証コマンド」の E2E 実行方法に合わせる。`port` が渡されていればそのポートで起動する
3. 生成された png を `Read` で開き、`state` に書いた画面が写っていることを確かめる。少なくとも最初と最後の 1 枚ずつは開く
4. `screens.ndjson` の各行に `flow` を足してマニフェストの `screens` に写す

## API

### 何を残すか

この issue が追加・変更した HTTP API ごとに、成功 1 件と、機能設計書の「エッジケースの決定」にある主要な失敗 1〜2 件を残す。1 issue で合計 4 件までにする。

実際にサーバへ送ったリクエストと、実際に返ったステータス・ヘッダ・本文をセットで残す。期待値から書き起こした応答や、テストダブルの応答を実行結果として載せない。データ更新が目的の API で、更新されたことが応答から読めない場合は、確認用の GET を 1 件足してよい (4 件に含める)。

アカウントとデータは確認用のものを使い、実在する個人情報を送らない。

### ファイルの書式

1 ケース 1 ファイル。1 行目が `$ ` に続く再実行できる curl コマンド、2 行目が空行、3 行目以降が `curl -sS -i` の出力である。

```text
$ curl -sS -i -X POST http://localhost:43123/api/members -H 'Content-Type: application/json' -H 'Authorization: <masked>' -d '{"email":"member@example.com"}'

HTTP/1.1 201 Created
content-type: application/json

{"id":"m_01","email":"member@example.com","status":"申請中"}
```

`workflow-create-pr` は 1 行目をコマンド、3 行目以降を応答として本文に埋め込む。出力が 60 行を超えたら 60 行で切り、`... (truncated)` の行を足す。

### 取る手順

1. `docs/design/DESIGN.md`「開発・検証コマンド」の手順で dev server をバックグラウンド起動する (`port` が渡されていればそのポート)。既に動いているサーバには相乗りしない
2. ケースごとに、コマンド行と実行結果を一時ファイルに書き、マスクと切り詰めをかけて本番のファイルにする

   ```bash
   mask_secrets() {
     sed -E \
       -e 's/(([Aa]uthorization|[Cc]ookie|[Ss]et-[Cc]ookie):[[:space:]]*)[^"<[:space:]][^"]*/\1<masked>/g' \
       -e 's/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+/<masked>/g' \
       -e 's/(^|[^A-Za-z0-9])(ghp_|gho_|ghs_|sk-)[A-Za-z0-9_-]{20,}/\1<masked>/g' \
       -e 's/AKIA[0-9A-Z]{16}/<masked>/g' "$1"
   }
   f=<evidence_dir>/api/01-post-members-ok.txt
   mkdir -p "$(dirname "$f")"
   cat > "$f.raw" <<'CMD'
   $ curl -sS -i -X POST http://localhost:43123/api/members -H "Content-Type: application/json" -H "Authorization: <masked>" -d '{"email":"member@example.com"}'

   CMD
   curl -sS -i -X POST http://localhost:43123/api/members -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d '{"email":"member@example.com"}' >> "$f.raw"
   mask_secrets "$f.raw" | awk 'NR<=62 {print} NR==63 {print "... (truncated)"}' > "$f" && rm "$f.raw"
   ```

   1 行目のコマンドは、認証値を最初から `<masked>` にして heredoc で書く。ヘッダの引数は二重引用符で囲む。`mask_secrets` はヘッダの値を次の二重引用符か行末までとみなすので、単一引用符で囲むと後ろの `-d` まで消える

   `mask_secrets` は `Authorization` / `Cookie` / `Set-Cookie` の値をスキームごと、JWT (`eyJ` で始まる 3 区切り)、`ghp_` / `gho_` / `ghs_` / `sk-` / `AKIA` で始まるトークンを `<masked>` に置き換える。1 行目のコマンドにも同じ置換がかかるので、書き忘れた認証値の保険になる
3. 全ファイルを書いたら、マスク漏れが無いことを確かめる。`workflow-create-pr` は同じパターンで最終本文を検査し、検出したら PR を作らずに止まる

   ```bash
   rg -n '(?i)(authorization|cookie):[[:space:]]*[^<[:space:]"]|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.|(^|[^A-Za-z0-9])(ghp_|gho_|ghs_|sk-)[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}' <evidence_dir>/api
   # 何も出なければよい
   ```

   パターンにかからない秘密 (独自形式の API キー・パスワード・個人情報) は目で見て消す。消した箇所は `<masked>` にして、応答の構造とステータスは残す
4. dev server を止める
5. 各ファイルをマニフェストの `api` に写す

マスクと検出のパターンは、2026-10-27 に 4 種のトークンと 3 種のヘッダを含む入力で反応すること、マスク済みの入力と `risk-assessment` のような紛らわしい語では反応しないことを確かめてある。
