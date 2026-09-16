---
name: transcribing-meeting-minutes
description: 会議・商談・インタビューの録音をMLX Whisperでローカル文字起こしし、決定事項・議論要旨・未決事項・アクションアイテムを時刻根拠付きの議事録へ整理する。「MTGの録音から議事録を作って」「m4aを文字起こしして要約」「会議音声を書き起こして」など、m4a・mp3・wav・mp4・mov・aac・flac・ogg・webmの音声または動画から議事録を作る依頼で使用する。音声の全文書き起こしだけが目的の場合にも使用する。
---

# 会議録音から議事録を作成

- 種別: スキル定義

音声を外部の文字起こしAPIへ送信せず、Apple Silicon Mac上で処理する。文字起こし全文を時系列で確認し、確定事項と提案を混同しない議事録を作成する。

## 前提

- macOS Apple Siliconで実行する。
- `ffprobe`、`ffmpeg`、`uvx`、`jq`を使用する。コマンドが無い場合は報告して停止する。
- 初回実行時はモデルとPython依存パッケージのダウンロードが発生する。
- 音声や文字起こしに含まれる秘密情報を、外部サービス、ログ、リポジトリへ送信・保存しない。

## ワークフロー

### 1. 入力と出力を決める

- 入力パスが無い場合だけユーザーへ確認する。
- 出力指定が無ければ、入力と同じディレクトリへ `<元ファイル名>_議事録.md` を作成する。
- ユーザーが全文書き起こしも求めた場合は `<元ファイル名>_文字起こし.txt` も作成する。
- 依頼が全文書き起こしのみで議事録が不要な場合は `<元ファイル名>_文字起こし.txt` だけを成果物とし、4〜6を省略して7へ進む。
- 元音声を上書き・移動・削除しない。

### 2. 音声を検査する

入力の存在、音声ストリーム、長さ、チャンネル数を確認する。

```bash
ffprobe -v error \
  -show_entries format=duration:stream=codec_name,sample_rate,channels \
  -of json "<recording>"
```

ファイル名から日時を推定する場合は、議事録に推定であることを明記する。参加者は会話内で出席が確認できる人物だけを記載し、単に名前が言及された人物を参加者へ加えない。

### 3. ローカルで文字起こしする

一時ディレクトリを作り、[scripts/transcribe.sh](scripts/transcribe.sh)を実行する。言語の指定が無ければ日本語を既定値とし、言語が不明な場合だけ`auto`を指定する。`auto`は音声冒頭から単一言語を選ぶ機能であり、複数言語を区間ごとに判定する機能ではない。言語が切り替わる区間を再確認するときは、その区間の言語コードを明示する。

```bash
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/meeting-minutes.XXXXXX")"
scripts/transcribe.sh "<recording>" "${work_dir}" ja
```

録音時間に比例して数分〜数十分かかるため、同期実行せず`{{@background-run}}: true`で起動する。完了まで定期的に出力を確認し、進捗をユーザーへ伝える。`transcript.json`、`transcript.txt`、`transcript.vtt`、`transcript.srt`、`transcript.tsv`が生成される。既存出力を上書きしない。

スクリプトは初回文字起こし後に[scripts/check_transcript_quality.sh](scripts/check_transcript_quality.sh)を実行する。`.segments[].text`の前後空白を除いた非空セグメントを単位とし、完全一致する同一テキストが20セグメント以上連続するか、100セグメント以上ある文字起こしで同一テキストが全体の20%以上を占める場合は、Whisperが失敗ループへ入った可能性が高いと判定する。その場合は次の処理を自動で行う。

1. 初回結果を`${work_dir}/first-pass/`へ退避する。
2. 前区間の文章を次区間へ引き継がず、語単位タイムスタンプと無音区間の幻覚抑制を有効にして全編を1回だけ再文字起こしする。
3. 再結果にも反復崩れがあれば終了コード70で停止する。崩れた結果から議事録を作らず、ユーザーへ報告する。

再実行された場合、後続処理では`${work_dir}/transcript.json`を正本として使う。`${work_dir}/first-pass/`は原因確認用であり、要約根拠には使わない。

再文字起こしのプロセス自体が失敗した場合は、`first-pass/`を含む失敗時の作業ディレクトリを証跡として保持する。既存出力を削除せず、新しい`work_dir`を作って最初から再実行する。

### 4. 全編を時系列で確認する

`transcript.json`を5分単位で読み、冒頭・途中・末尾を省略せず全区間を確認する。5分は長時間録音を読み落とさず扱うためのレビュー単位であり、議題の区切りには使用しない。

```bash
jq -r '
  .segments
  | group_by((.start / 300) | floor)[]
  | (.[0].start / 300 | floor) as $bucket
  | "\n===== \($bucket * 5)〜\($bucket * 5 + 5)分 =====\n"
    + (map(.text) | join(""))
' "${work_dir}/transcript.json"
```

次を抽出する。

- 会議の目的と背景
- 決定事項
- 議論の要旨と判断理由
- 未決事項・リスク
- アクションアイテムの担当、内容、期限
- 重要事項の開始時刻
- 聞き取りに確信が持てない固有名詞、数値、日付

認識確度が低い区間は、平均対数確率が低い順に確認する。数値は誤認識区間を探すための手掛かりであり、誤りの断定には使わない。

```bash
jq -r '
  [.segments[]]
  | sort_by(.avg_logprob)
  | .[:20][]
  | "\(.start)\t\(.avg_logprob)\t\(.text)"
' "${work_dir}/transcript.json"
```

### 5. 不確実な箇所を再確認する

氏名、金額、日付、期限、製品名、決定を左右する表現が不明瞭な場合は、該当区間だけ語単位タイムスタンプ付きで再文字起こしする。モデルは3で使用したもの (`MLX_WHISPER_MODEL`、既定値`mlx-community/whisper-large-v3-turbo`) を使う。3で言語コードを指定した場合だけ同じコードを`--language`へ渡し、`auto`を指定した場合は`--language`行を省略する。複数区間を再確認する場合は、区間ごとに一意な`clip_id`を付けて出力を分け、開始・終了秒と出力パスを記録する。

```bash
clip_id="<start-seconds>-<end-seconds>"
recheck_dir="${work_dir}/recheck/${clip_id}"
mkdir -p "${recheck_dir}"

uvx --from mlx-whisper mlx_whisper "<recording>" \
  --model "${MLX_WHISPER_MODEL:-mlx-community/whisper-large-v3-turbo}" \
  --language "<3で指定した言語コード。autoの場合はこの行を省略>" \
  --clip-timestamps "<start-seconds>,<end-seconds>" \
  --word-timestamps True \
  --output-dir "${recheck_dir}" \
  --output-name transcript \
  --output-format all \
  --verbose False
```

再確認しても確定できない場合は`要確認`と記載する。文脈から推測した値を確定事項、参加者、担当、期限として書かない。

品質チェックが通っていても、固有名詞や専門用語の誤認識は残りうる。文字起こしだけから一般的な業界用語へ補正した場合は、補正後の語を確定扱いせず、議事録へ`正式名称要確認`と明記する。

### 6. 議事録を作成する

録音内容に合わせ、不要な空セクションは省きつつ次の順序を基本とする。

```markdown
# <会議名>

- 種別: 議事録
- 日時: <日時または要確認>
- 所要時間: <分>
- 参加者: <確認できた参加者または要確認>
- 元録音: `<ファイル名>`

## 会議の目的
## 決定事項
## 主な議論
## 未決事項
## アクションアイテム
| 担当 | 対応内容 | 期限 | 音声位置 |
|---|---|---|---|
## 参考タイムライン
```

次の基準を守る。

- 決定された内容だけを「決定事項」へ記載する。「検討する」「案として」は未決事項へ分ける。
- 発言の逐語的な羅列ではなく、結論と根拠が追える粒度で具体的に要約する。
- アクションアイテムは担当、期限が録音で明示されていない場合に`未定`とする。
- 重要な決定とアクションアイテムへ、元音声へ戻れる開始時刻を付ける。
- 機密情報を議事録へ含める必要がない場合は省く。

### 7. 検証して報告する

以下をすべて満たすまで修正する（全文書き起こしのみの場合は議事録に関する項目を除く）。

- 最終セグメントの終了時刻と録音時間の差を確認する。差が大きい場合は末尾区間を試聴または波形・音量で確認し、正常な無音なのか文字起こし欠落なのかを判別する。
- 議事録を作成した場合、冒頭・中央・末尾から最低1区間ずつ、議事録との対応を確認している。
- 議事録を作成した場合、すべての決定事項が文字起こし内の根拠へ戻れる。
- 議事録を作成した場合、提案を決定事項として記載していない。
- 議事録を作成した場合、氏名、数値、日付、担当、期限を推測で補っていない。
- 自動品質チェックが成功し、`first-pass/`がある場合は再文字起こし後の結果だけを要約根拠に使っている。
- 出力ファイルが存在し、空でなく、議事録の場合は表が崩れていない。
- 元音声と依頼範囲外のファイルへ変更を加えていない。

最後に、成果物のパス、不確実な箇所、一時文字起こしの保存場所を簡潔に報告する。

## 依拠する外部仕様

2026-09-09時点で、MLX Whisperの[音声読込実装](https://github.com/ml-explore/mlx-examples/blob/main/whisper/mlx_whisper/audio.py#L38)、[出力処理](https://github.com/ml-explore/mlx-examples/blob/main/whisper/mlx_whisper/writers.py#L47)、[言語判定](https://github.com/ml-explore/mlx-examples/blob/main/whisper/mlx_whisper/transcribe.py#L147)を確認した。依存コマンドやCLI引数の挙動が変わった場合は、現行の公式実装と照合する。

## 使用例

```text
/transcribing-meeting-minutes /Users/me/Downloads/weekly.m4a
```

```text
この英語の商談録音から、決定事項と担当者別TODOを含む日本語議事録を作って:
/Users/me/Downloads/customer-call.mp3
```
