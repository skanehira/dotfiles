# PoC 検証 (dev-spec のフェーズ 5)

本書の「手順 N」は本書の中の段階で、SKILL.md のフェーズ番号とは別である。dev-spec のフェーズを指すときは「dev-spec のフェーズ N」と書く。

## 目的

FEASIBILITY.md に書かれた PoC 計画を**実際に実行して**、技術的実現可能性を機械検証する。「できるはず」という自己申告を、PoC コードの実行結果という観測可能な事実に置き換えてから設計書生成に進む。

## POC_STATUS 行 (機械判定用の状態書式)

各 PoC 計画は見出し (`### PoC: <名前>`) の直下に必ず 1 行、次の書式の status 行を持つ (dev-spec のフェーズ 4 が `status=unresolved` で書き、本フェーズが更新する)。フィールドの順序は固定:

```
<!-- POC_STATUS: id=<id>, blocker=<true|false>, status=<unresolved|verified|fallback_adopted|scope_reduced>, confidence=<0.0-1.0|manual> -->
```

`confidence` は、手順 3 で自動解決したときは結果 JSON の `confidence` の値、手順 4 で人間が決めたときは `manual` と書く。

- `status=unresolved`: 未検証 (dev-spec のフェーズ 4 直後の初期値。confidence は省略)
- `status=verified`: 検証済み、当初案で進める
- `status=fallback_adopted`: 当初案不成立、ユーザーが fallback 採用を決定
- `status=scope_reduced`: ユーザーがスコープ縮小を決定

dev-spec のフェーズ 6 のゲートはこの行を `rg 'POC_STATUS:.*blocker=true.*status=unresolved'` で判定する。**本文の説明ではなくこの行が唯一の判定ソース**である。行がある計画で status の更新を忘れた場合は、ゲートが閉じたまま残る (安全側)。行そのものが無い計画は抽出にも rg の判定にも現れないので、見出しと行の件数の照合で見つける。照合は feasibility-check.md の完了条件・本書の手順 1・dev-spec のゲート (SKILL.md「ゲート条件」) の 3 か所で行う。

## ワークフロー

### 手順 1: 対象の抽出

検証対象は 2 か所から集める。

1. **FEASIBILITY.md の PoC 計画**: docs/design/FEASIBILITY.md を Read し、`status=unresolved` の POC_STATUS 行を抽出する。その前に `rg -c '^### PoC:' docs/design/FEASIBILITY.md` と `rg -c 'POC_STATUS:' docs/design/FEASIBILITY.md` の件数を比べ、食い違えば行の無い計画に計画本文の値で `status=unresolved` の行を足してから抽出する
2. **設計中に見つかった blocker=true の要素**: dev-spec のフェーズ 6・7 が設計の途中で差し戻した場合、設計書に `POC_NEEDED` マーカーが残っている。次のコマンドで拾う (dev-impl の開始ガードと同じコマンド):

   ```bash
   rg -n 'POC_NEEDED:.*blocker=true' docs/design/DESIGN.md docs/design/features/ 2>/dev/null
   ```

   判定は出力の行数で行う。最初の dev-spec のフェーズ 5 では DESIGN.md も features/ もまだ無いことが多く、rg は終了コード 2 を返すが、警告を捨てているので無いファイルは 0 件として読める。

   FEASIBILITY.md に同じ id の PoC 計画が無いマーカーは、マーカーの値から計画を FEASIBILITY.md の「## PoC計画」節に足す (見出し、`status=unresolved` の POC_STATUS 行、`**id**`、`**目的**` = マーカーの scope、`**risk**`、`**blocker**`)。成功基準はマーカーがある節の文脈から起こし、ユーザーに確認してから書く。FEASIBILITY.md が「不確実性なし」の記録だけ (feasibility-template.md「ドキュメント構造」の形) なら、その記録の行を消して同じ「ドキュメント構造」の構造で書き直す (FEASIBILITY.md が無ければ同じ構造で作る)

抽出した計画の扱い:

- **blocker=true**: このフェーズでの検証が必須
- **blocker=false**: 任意。risk=high なら検証を推奨し、ユーザーに確認する
- **対象 0 件**: 「PoC 検証: 対象なし (スキップ)」と表示して dev-spec のフェーズ 6 へ進む

### 手順 2: tech-investigation の並列 fan-out

対象の PoC 計画 1 件につき、サブエージェント `tech-investigation` を 1 本起動する (モデル: opus を明示)。互いに独立な調査なので全件を並列に起動し、全件の完了を待ってから手順 3 へ進む。手順 4 の「再試行」から戻ったときは、再試行を選んだ計画だけを起動する。

- 説明: `PoC: <id>`
- モデルを明示する理由: 調査 fan-out は opus を明示する (~/.claude/rules/core/orchestration.md の割当表)。agent 側 frontmatter も opus だが、明示を忘れると無音でセッションモデルの継承に落ちるので二重に指定する
- 次の指示文を渡す。`scope` は計画の `**目的**` 行、`risk` は `**risk**` 行、`blocker` は POC_STATUS 行から取る:

```
以下の PoC 計画を検証してください。

- marker: id=<id>, scope=<目的の 1 行>, risk=<risk>, blocker=<blocker>
- context_paths: docs/design/FEASIBILITY.md (PoC 計画の全文と文脈を読むこと)
- output_path: <scratchpad>/tech-investigation-<id>.json
- workspace_dir: <scratchpad>/poc-<id>/
- 追加指示: <手順 4 の「再試行」から起動するときだけ、ユーザーが答えた追加指示。それ以外は「なし」>

成功基準は FEASIBILITY.md の該当 PoC 計画に記載のものを使うこと。追加指示があれば、それに従って前回と変えて検証すること。
```

手順 1 の項目 2 (設計書のマーカー) から足した計画では、`context_paths` にマーカーがある `docs/design/DESIGN.md` または `docs/design/features/<機能名>.md` を加える。

### 手順 3: 結果の分類と反映

各 subagent の output_path から結果 JSON を Read し、次の表で分類する。**この表が解決判定の正本である。** tech-investigation の JSON にある `blocker_resolved` は判定に使わない (ドキュメントを確認しただけの結果にも true が付きうるため)。**agent の失敗や低確信をパス扱いにしない** (未検証は未検証のまま人間に回す):

| 結果 | 扱い |
| --- | --- |
| `result: verified` かつ `confidence >= 0.7` かつ `investigation_steps` に PoC コードを実行した旨の記録 (実行したコマンドと結果) がある | 自動で解決。POC_STATUS を `status=verified, confidence=<値>` に更新 |
| `result: verified` で上の条件を満たさない (confidence < 0.7、または PoC コードを実行せずドキュメント確認だけで verified とした) | **自動解決しない** (実行結果の裏付けが無い)。手順 4 の人間判断へ |
| `result: partial` / `fallback_needed` | 手順 4 の人間判断へ |
| stdout が `INVALID_MARKER` / `NO_CONTEXT_DOCS` / `INVESTIGATION_FAILED`、または JSON が読めない・agent が応答しない | **その計画は未検証のまま** (status は unresolved を維持)。手順 4 の人間判断へ (選択肢の「再試行」を使う) |

`investigation_steps` は文章の配列なので、PoC コードを実行した記録があるかは各行を読んで判断する。

解決した計画は、FEASIBILITY.md の「## PoC 結果」節に 1 件 1 項で追記する (節が無ければ末尾に作り、あれば項だけを足す)。手順 3 で自動解決した計画も、手順 4 で人間が決めた計画も、同じ書式で書く:

```markdown
## PoC 結果

### <id> — <status> (<判定の主体>)
- 検証日: YYYY-MM-DD
- 観測した事実: (実行したコード・コマンドと出力の要点。subagent が失敗したときはその旨)
- 結論: 成功基準に対する判定
- 推奨アプローチ: (結果 JSON の `recommended_approach` をそのまま写す。JSON が無いときは「なし」)
- 採用した判断: (手順 4 で人間が決めたときだけ) 選んだ選択肢とその理由
- fallback: (fallback_adopted のときだけ) 採用した代替案と採用理由、当初案の却下理由
- 外した範囲: (scope_reduced のときだけ) 今回のスコープから外した機能要素
```

| 欄 | 取りうる値 |
| --- | --- |
| `<status>` | `verified` / `fallback_adopted` / `scope_reduced` (POC_STATUS 行の status と同じ値) |
| `<判定の主体>` | 自動解決なら `confidence <値>` (例: `confidence 0.85`)、人間が決めたなら `判断: ユーザー` |

見出しは `### PoC:` で始めない (feasibility-check.md の完了条件と dev-spec のゲートが `^### PoC:` を PoC 計画の数として数えるため)。dev-spec のフェーズ 6 は、この項を design-doc.md「入力と転記」の規則 1・2 で DESIGN.md へ写す。

### 手順 4: 人間判断 (Stop)

自動解決できなかった計画ごとに、**勝手に設計を曲げず**ユーザーに判断を仰ぐ。次のように聞き、選択肢を番号付きでメッセージに並べて、採用する番号を 1 つ答えてもらう。

```
PoC「<id>」が自動解決できませんでした。

理由: <verified だが confidence 0.6 / PoC 未実行 / fallback_needed / agent 失敗 など>
観測した事実: <要点>

どうしますか? 番号で答えてください。
```

| 番号 | 選択肢 | 意味 |
| --- | --- | --- |
| 1 | この結果で採用 | verified 扱いにする |
| 2 | fallback 採用 | <tech-investigation が提示した代替案の要点> |
| 3 | スコープ縮小 | この機能要素を今回のスコープから外す |
| 4 | 再試行 | PoC を追加指示付きで再実行する |
| 5 | 再検討 | dev-spec のフェーズ 4 に戻って前提から見直す |

選択肢 2 は、結果 JSON に `fallback` (代替案) があるときだけ並べる。無いとき (verified だが確信度が低い結果、subagent の失敗) は 2 を除いて並べる。採用する代替案の出所が無いまま fallback 採用を選べないようにするためで、残りの番号は振り直さない。

選択肢 1〜3 では、POC_STATUS を対応する status (1 = `verified`、2 = `fallback_adopted`、3 = `scope_reduced`) と `confidence=manual` に更新し、手順 3 の書式で「PoC 結果」に項を足す (見出しの判定の主体は `判断: ユーザー`、「採用した判断」の欄に選んだ選択肢と理由を書く)。選択肢ごとの続き:

- **再試行**: status を unresolved のまま残す。何を変えて試すかを「どの条件を変えて再試行しますか?」と聞いて自由入力で答えてもらい、その答えを手順 2 の指示文の `追加指示:` 行に入れる。再試行を選んだ計画だけを手順 2 で起動し直す
- **再検討**: status を unresolved のまま残して dev-spec のフェーズ 4 に戻る。feasibility-check.md は既存の PoC 計画の id・POC_STATUS 行・「PoC 結果」を保持し、見直しで増えた計画だけを unresolved で足す
- **スコープ縮小**: 外した範囲をユースケースとストーリーにも反映する。反映しないと、外した要素の受け入れ基準が残り、dev-spec のフェーズ 8 の観点 1 が落とし漏れとして報告する
  1. USER_STORIES.md がある構成では、外した機能要素だけを担うストーリーを Won't の表へ移し、優先順位サマリーの件数を直す (usecase-description.md 手順 9.2 の表の「(3) Won't へ移す」と同じ操作)。そのストーリー番号を接頭辞に持つ受け入れ基準の行を USECASES.md から消す (ストーリーの一部だけを外すときは、外した部分に当たる受け入れ基準の行だけを消す)。USER_STORIES.md が無い構成では USECASES.md の該当行だけを消す
  2. 受け入れ基準が 1 行も残らないユースケースは、ユースケースごとスコープから外れている。その節を USECASES.md から消す (番号は振り直さず欠番にする。他のユースケースの番号は機能設計書と親 issue のタイトルから参照されているため)。被覆チェックは受け入れ基準が 0 行のユースケースを検出しないので、消し忘れると dev-spec のフェーズ 9 が子の無い親 issue を作り、dev-impl がその親を close できない
  3. docs/design/features/ が既にある (dev-spec のフェーズ 6・7 から差し戻された) ときは、消した受け入れ基準の写しを各機能設計書の「テスト方針」の表と `E2E 対象動線:` 行から消し、消したユースケースを「対象 UC」から外す。担うユースケースが 1 つも残らない機能設計書は、消すかをユーザーに確認する
  4. USER_STORIES.md がある構成では、usecase-description.md の手順 9 (書き戻しと被覆チェック) を流し直す

### 手順 5: ゲート判定 (機械)

フェーズ完了前に必ず実行する:

```bash
rg -n 'POC_STATUS:.*blocker=true.*status=unresolved' docs/design/FEASIBILITY.md
```

0 件になるまでこのフェーズを完了扱いにしない (1 件以上残っていれば手順 2 または手順 4 に戻る)。

手順 1 の項目 2 (設計書のマーカー) から足した計画があった場合は、本フェーズの後に差し戻し元の dev-spec のフェーズ 6・7 に戻り、結果を設計へ反映してマーカーを除去する。除去されたかは dev-spec のフェーズ 8 の開始前の検査が確かめる。

## 後段との連動

- dev-spec のフェーズ 6 (design-doc) は、FEASIBILITY.md の「PoC 結果」を入力にとり、3 種の転記を行う (規則は design-doc.md「入力と転記」): verified の結果 (結論と推奨アプローチ) を技術選定の根拠として「アーキテクチャと技術選定」に反映する / `status=fallback_adopted` / `scope_reduced` の結果を同節に当初案 = 却下案、fallback / スコープ縮小後の案 = 採用案として転記する / 未検証で残った `blocker=false` の計画を `POC_NEEDED` マーカーとして該当節 (機能単体の契約なら dev-spec のフェーズ 7 が docs/design/features/ の該当ファイル) に転記する
- 未検証で残った `blocker=false` のマーカーは、ちょうど 1 つの子 issue の DoD に「検証してマーカーを除去し、FEASIBILITY.md の POC_STATUS と『PoC 結果』を更新する」が入り、実装ループの中で解消される (issue-template.md「子 issue テンプレート」の DoD)
- 実装ループ (`/dev-impl`) は起動時に docs/design/DESIGN.md / docs/design/features/ の `blocker=true` マーカー残存をチェックし、見つけたら実装に入らず本フェーズへの差し戻しを案内する (安全網)
