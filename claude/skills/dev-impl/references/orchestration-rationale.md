# dev-impl オーケストレーション方針の根拠 参照

`dev-impl/SKILL.md` の「モデル方針」「フェーズ実装を subagent に委譲する理由」「Step 3」から参照される、**実測にもとづく方針の根拠**。方針そのもの (どの agent をどの model で起動するか、上限はいくつか) は SKILL.md 本体の表が正で、ここには「なぜその値なのか」と「どの観測で決めたか」だけを置く。値を変えるときはここの実測と突き合わせる。

## 目次

- [修正ラウンドのモデル昇格の根拠](#修正ラウンドのモデル昇格の根拠)
- [review-adversarial が sonnet である根拠](#review-adversarial-が-sonnet-である根拠)
- [フェーズ実装を subagent に委譲する根拠](#フェーズ実装を-subagent-に委譲する根拠)
- [spawn 予算の根拠](#spawn-予算の根拠)
- [内部呼び出し subagent の役割詳細](#内部呼び出し-subagent-の役割詳細)

## 修正ラウンドのモデル昇格の根拠

**ラウンド 1 で解消しなかった fatal は、指摘箇所の局所修正では閉じない性質のものが多い。** 実測: `opus` の fix は毎ラウンド「指摘された high」を必ず解消したのに、そのたびに同じ族の隣接箇所へ新しい high が出た。あるフェーズでは 3 ラウンドすべてがこの形を繰り返し (指摘 → 解消 → 隣接箇所に新規)、high の出所は同じ 2 ファイルの間を往復したまま上限に達して停止した。個別のエッジケースを潰す作業になっていて、状態遷移の不変条件という根が閉じていなかった。

そこで**ラウンド 2 以降は `model: "fable"` に上げ、指示文で「指摘箇所を局所的に塞ぐ前に、当該箇所が属する不変条件を洗い出して族ごと閉じる」ことを求める** (指示文の全文は [references/phase-execution.md](./references/phase-execution.md) の `## 4.2d: 修正ラウンドの implementer 起動`)。ラウンド 3 でも解消しなければ従来どおり `phase_fix_exceeded` でエスカレ停止する — **モデルを上げても閉じない fatal は、実装の腕ではなく設計の問題である**可能性が高く、人間の判断を仰ぐべき局面だと見なす。

- `agent-spawn-guard` hook は **model の未指定だけを弾き、規定と違う値でも明示されていれば意図的な override として通す** (`claude/hooks/agent-spawn-guard.ts` の `validateAgentSpawn`)。この昇格に hook の改修は要らない
- この昇格により、当該ラウンドだけ「実行器のモデル > 検証器のモデル」となり `rules/core/orchestration.md` の原則を満たさなくなる。**検証器 (review-*) を上げるのではなく実行器だけを上げるのは、ラウンド 2 に至った時点で不足しているのが検出力ではなく修正の設計力だと実測で分かっているため** (検出は毎ラウンド機能しており、新しい high を実行証拠つきで出し続けている)

## review-adversarial が sonnet である根拠

- **review-adversarial が `sonnet` である理由**: 同一セッション・同一フェーズ群での直接比較 (2026-08 のセッションログ実測) で、opus は 20 spawn・2.55 ドル/spawn で high 3 件 (0.15 件/spawn)、sonnet は 21 spawn・2.51 ドル/spawn で high 19 件 (0.90 件/spawn) だった。**1 spawn あたりの金額はほぼ同一で、単価が 1/5 の sonnet は同じ予算で 3.8 倍のターンを回せるため、実際に壊して確かめる本 agent の作業様式と噛み合う**。sonnet の findings は空虚ではなく、TOCTOU 並行削除を実際に再現し修正前ロジックで 20/20 再現するところまで確認する等、実行証拠を伴っていた。この 1 点で `rules/core/orchestration.md` の原則「実行器のモデル ≤ 検証器のモデル」を満たさなくなるが、当該原則は「検証が実行より弱いと骨抜きになる」ことを避けるための代理指標であり、**検出力の実測が代理指標に優先する**。切り替え後は high 検出件数の推移を監視し、opus 時の 0.15 件/spawn を下回り続けるようなら opus に戻す。

## フェーズ実装を subagent に委譲する根拠

例外にする根拠は、dev-impl だけが持つ「フェーズを 100 本単位で回す」性質にある (実測値はいずれも 2026-07 の dev-impl 実行 7 セッション):

- メインループ直営では**フェーズ境界でコンテキストが一度も下がらず単調増加する**。実測で 160k → 286k → … → 980k → 自動圧縮 106k と推移し、平均コンテキストは 443,863〜515,258 トークンに収束した。cache read 48.7 億トークンの実体は「平均 475k × 10,247 リクエスト」であり、1 リクエストの単価ではなく**往復回数 × 常駐コンテキスト**が支配的だった
- 委譲の固定費はフェーズ 1 本あたりで見れば小さい (U0 spike 実測: implementer 1 spawn 6.39 ドル、検査 3 観点 1.83 ドル、修正 1 ラウンド 2.96 ドル の計 11.18 ドル)。単発タスクなら固定費が勝つが、フェーズ数だけ常駐コンテキストが積み上がる dev-impl では逆転する
- **待ちを親に集約できる。** main の cache write は全量 1 時間 TTL、subagent は全量 5 分 TTL (ハーネス仕様、スキルから制御不可)。子を待つ subagent は 5 分超のギャップでキャッシュを失効させる (実測: 失効 62 件のうち 32 件がこれ)。実装を葉の subagent に閉じ込め、レビューの起動と待機を 1 時間 TTL の main に置くことで、同じ待ち時間でもキャッシュが生き残る

**implementer は葉であること (子 subagent を起動しないこと) が例外の前提条件**。葉の agent は実測で失効ゼロだった (architecture-guard 975 ギャップ / review-quality 55 / review-spec-compliance 165 のいずれも 0 件)。葉性は指示文ではなく `claude/agents/dev-impl-implementer.md` の `tools` から `Agent` を除くことで構造的に強制する (subagent には親の hooks が届かないため、指示文では違反を検出できない)。

## spawn 予算の根拠

上限値そのものは SKILL.md 本体の Step 3 のカウンタ表と「spawn 予算の意図」の更新表が正。ここには測定と算出の内訳を置く。

- 根拠: subagent を最も使ったセッションは 129 spawn でフェーズ単価が最悪 (116.4 ドル / フェーズ、subagent が全体の 66.8%) だった (2026-07 の実測)。2026-08 の実測でも、4 フェーズで 66 spawn (16.5 spawn / フェーズ) のうち 53 がレビュー系で、全体コストの 35% を占めていた。**このとき JSONL に記録されていた `spawn` は 44 件で、実際の 66 件に対し 22 件 (33%) が記録漏れしていた** — 記録が欠けると `phase_spawns` の上限判定が実態より小さい値で走るので、下記の全件記録は予算ゲートの前提そのものである
- `phase_spawns` の上限 33 の内訳 (最悪ケース = 最後の issue): implementer 1 + 初回検査 5 (guard 1 + review 最大 4) + (fix 1 + 再検査 最大 5) × 3 ラウンド = 24 に、**同じフェーズで正当に起きうる残りを足した値**: 4.2b の `fix-lsp-warnings` 1 + 4.2e のテストゲート再試行 3 + 報告不整合の再起動 3 + 汚染検出によるやり直し 2 = 9。合計 33。**以前の 24 は検査ラウンドだけを数えた値で、本文自身が挙げる正当な経路を足すと超えてしまっていた** (正常な作業が上限で止まる偽陽性になる)。上限に当たったら `spawn_budget_exceeded` で止めてよい (安全網として機能させる)。再検査は 4.2d 手順 5 のとおり「fatal を出した観点 + guard」に絞るため通常は 2〜3 に収まるが、全観点が同時に fatal を出す最悪ケースを上限に据える (上限は安全網であって想定値ではない)
- `run_spawns` の上限係数は **20 (spawn / issue)** で、**実測から取る**。上に挙げた 2 件の測定はいずれも 1 フェーズあたり 14.8〜16.5 spawn であり、修正ラウンドが 1〜3 回入る通常のフェーズはこの範囲に収まる。20 はその上に予備を持たせた値で、**フェーズ単体の上限 33 より下に置く** (係数を 33 に揃えると run 側の予算がフェーズ側より先に効くことが無くなり、安全網として機能しなくなる)。**「最小構成 4 体 (implementer 1 + guard 1 + review-adversarial 1 + review-tdd 1) + 修正 1 ラウンド」から見積もった旧値 8 は実測の半分で、正常に完走する run を止めていた** — 4 フェーズ 66 spawn の run は open 4 件なら予算 32 で、2 フェーズ目の途中で `spawn_budget_exceeded` に当たる

- **`OPEN × 20` を `run_spawns` と直接比べてはならない。** 前者は「これから使ってよい量」、後者は「すでに使った量」で、比べる単位が違う。直接比べると issue を close するたびに上限が下がるので、**正常に完了した作業そのものが停止理由になる** — 消費済みの `run_spawns` が残 `OPEN × 係数` を上回った時点で、次の 1 件を close した瞬間に breach する。実測 (5 フェーズ完了で `run_spawns` 74 = 14.8 spawn / フェーズ) のペースなら、残 `OPEN` が 4 件を切ったあたりでこれが起きる。さらに Step 5 (ゴール達成判定) では定義上 `OPEN` が 0 件になるため上限も 0 になり、`review-spec-compliance` / `review-product-readiness` の起動が必ず上限違反になる
- **再入で予算が増えるのは意図した挙動である。** `spawn_budget_exceeded` は「再実行で解決しうる」停止理由に分類されている (「エスカレ停止時の挙動」の表) ので、再入で予算が一切増えないなら、再実行しても同じ状態のまま即座に再停止して何も解決しない。予算の追加付与を人間の再起動に紐づけることで、1 セッション内の暴走は有限の `run_spawns_budget` で止めたまま、正当な継続だけが人間の判断を挟んで前進する

- 記録が欠けると `run_spawns` の予算判定が実態より小さい値で走る。**フェーズを閉じる直前 (4.2e 手順 4) に成果物と突合して補記する**のが二段目の歯止めだが、成果物 JSON を出さない fix-lsp-warnings は補記でも拾えないので、一段目 (起動前の記録) を落とさないことが要点である

## 内部呼び出し subagent の役割詳細

SKILL.md 「関連スキル / agent」から参照する。model の割当と根拠は SKILL.md 本体の「モデル方針」の表が正で、ここには各 agent が何を検査・実装するかを置く。

- **dev-impl-implementer**: フェーズ 1 本を TDD で実装する葉の agent (Step 4.2a `mode: implement` は `model: opus`、Step 4.2d `mode: fix` はラウンド 1 が `opus` でラウンド 2 以降が `fable`。いずれも明示)。`tools` に `Agent` を持たないため子 subagent を起動できず、5 分 TTL のキャッシュ失効を構造的に避ける。フェーズスコープのテストのみ実行し、コミット・`docs/` 編集・全体スイート実行はしない。全文報告を `report_path` に Write し、SendMessage では要約だけを返す (規約の全文は `claude/agents/dev-impl-implementer.md`)
- **tech-investigation**: 実装中に新たな技術検証が必要になった場合の個別呼び出しのみ (起動前の PoC は dev-spec フェーズ 5 の責務)
- **architecture-guard**: Clean Arch / DDD 境界違反検出、機械判定 (Step 4.2c の fan-out に毎フェーズ含める、haiku)
- **fix-lsp-warnings**: Lua/Neovim の LSP 警告修正 (Step 4.2b、haiku)。修正する agent なので検査 fan-out には混ぜず単独・逐次で走らせる
- **review-tdd / review-quality / review-product-readiness**: Step 4.2c から `model: opus` 明示で並列起動 (観点 gating・起動条件は Step 4.2c 参照)。review-quality は rules 準拠 + アーキテクチャ heuristic を統合。review-product-readiness は実機 chrome-devtools MCP 操作で UX 横断項目 (ナビ到達 / ErrorBoundary / 空状態 / loading / SEO meta / 404 / logout) を検査 (Step 5.2 の G_E2E 判定も担当)
- **review-adversarial**: Step 4.2c から `model: sonnet` 明示で並列起動する敵対的レビュワー。3 レンズ (A: エッジケース/エラーパスを能動的に攻撃し実際に実行して落とす、B: テスト弱体化・トートロジー化・アサーションの空虚化・skip 隠蔽の意味論検知、C: PHASE_CONTEXT を信用せず `docs_dir` の TODO.md から当該フェーズの節を自分で読み直し、その完了主張に反証を試みる) で検査。**毎フェーズは `mode: weakening_only` (レンズ B のみ) で走り、消費型資源・認証・テスト差分なしの大量実装・最後の issue のフェーズだけ `mode: full` (A+B+C) に上げる** (Step 4.2c の mode 決定表)。機械スキップ述語 (Step 4.2c 参照) を満たせば skip 可。`test_weakened` / `vacuous_assertion` / `skip_added` / `tautological_test` は severity と confidence に関わらず修正ラウンドに乗せず、トレース確認の経路に直結する (詳細は Step 4.2d)

- **review-spec-compliance**: Step 5.2 から `model: opus` 明示で起動する第三者受入監査 (mode: post-impl)。承認ハッシュの独立照合・自動系ゴール検証コマンドの独立再実行・成果物全体 ↔ 詳細設計の突合・検証コマンドの空虚性検査。PHASE_CONTEXT 抜粋は渡さず docs を自分で全文 Read させる (被監査者が編纂した入力を信用しない)。`PRODUCT_MODE=cli` では G_E2E 検証コマンドの実行もこの agent が担当する (review-product-readiness は起動しないため)
- **security-guidance プラグイン**: セキュリティレビューはこのプラグイン (Edit/Write 時の pattern 検知 + Stop hook の LLM diff review) に委譲。自作 subagent は持たない

**空虚テスト検出の分担**: review-tdd の `vacuous_negative_assertion` は**新規に書かれたテストそのものの空虚性**を、review-adversarial レンズ B の `vacuous_assertion` は**基準時点 (PHASE_START_SHA) からの空虚化**を見る。同一フェーズで両者が同種の指摘を上げることがあるが、検査している次元が違うため統合しない (統合するとどちらか一方の次元が検査されなくなる)。
