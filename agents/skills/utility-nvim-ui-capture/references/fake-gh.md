# fake `gh` で決定的なデータを作る

UI の確認に実 API を使うと、データが変わる・レート制限に当たる・意図しない副作用が起きる。`gh` を PATH の先頭に置いた偽物に差し替え、GraphQL の応答を fixture から返す。

## 1. 偽の `gh` を作る

プラグインが `gh api graphql --input -` を使う場合、stdin に `{query, variables}` の JSON が来る。クエリの特徴で fixture を選ぶ:

```bash
#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="${FIXTURE_DIR:-$(cd "$(dirname "$0")/../fixtures" && pwd)}"
input="$(cat)"

case "$input" in
  *"fields(first: 50)"*)
    cat "$FIXTURE_DIR/detail.json"
    ;;
  *"items(first:"* | *"orderBy"*)
    cat "$FIXTURE_DIR/items.json"
    ;;
  *)
    printf '%s\n' '{"data":{}}'
    ;;
esac
```

`chmod +x` し、`gh` という名前で保存する。スクリプトの `--path <偽 gh のディレクトリ>` を渡せば、nvim の `gh` 呼び出しがこちらに向く。

## 2. fixture を用意する

fixture の JSON は、プラグインが期待する GraphQL の形に合わせる。プラグインのテスト用 fixture があればそれをコピーし、スクリーンショット用に項目数・タイトル・ラベル・担当者・進捗を調整する。

- 詳細クエリ: project のタイトル、fields、views、items の totalCount
- items クエリ: 各 item の content、fieldValues、labels、assignees、subIssuesSummary
- 必要なら複数ページ (`hasNextPage`) や空の列も入れる

## 3. 注意

- 実 API を叩かない。スクリーンショットは再現可能であるべき
- 偽 `gh` は実行権限を付け、`PATH` の先頭に置く
- 偽 `gh` が想定外のクエリを受けたら `{"data":{}}` を返し、UI が空にならないか確認する
- プラグインが REST (`gh api repos/...`) も使うなら、`$1` や引数を見て分岐を足す
