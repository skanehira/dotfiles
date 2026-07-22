# PHASE_CONTEXT テンプレートと抜粋ロジック (dev-impl Step 4.1.5)

ファイルに書く PHASE_CONTEXT:

```yaml
product_mode: <cli|webapp|unknown>       # Step 1 で DESIGN.md スタンプから判定した PRODUCT_MODE
phase_name: <フェーズN: 名前>           # TODO.md の見出しから
phase_start_sha: <SHA>                   # Step 4.1 で記録
phase_tasks: |                            # TODO.md の該当フェーズセクション全文
  <TODO.md 該当部分を rg / awk で抽出>
design_overview: |                        # DESIGN.md 関連節抜粋 (上限あり、詳細は抜粋ロジック参照)
  <主要コンポーネント / 非機能目標 / ゴール のうち、現フェーズに関連する節>
design_overview_path: docs/DESIGN.md      # 抜粋で不足する場合に subagent が自分で Read するための固定 path
design_detail: |                          # DESIGN_DETAIL_APP.md / DESIGN_DETAIL_INFRA.md 関連節抜粋 (上限あり、詳細は抜粋ロジック参照)
  <API / スキーマ / シーケンス / 実装ガイド / リソース定義 / CI/CD のうち、現フェーズに関連する節。APP / INFRA どちら由来かを見出しに付記>
design_detail_app_path: docs/DESIGN_DETAIL_APP.md     # 抜粋で不足する場合に subagent が自分で Read するための固定 path
design_detail_infra_path: docs/DESIGN_DETAIL_INFRA.md # 同上 (インフラ系フェーズのみ関連することが多い)
related_source_files:                     # subagent が Read すべき既存ファイル一覧
  - <Glob で抽出した関連ファイル path>
related_rules_paths:                      # rules/core + 言語別 rules
  - rules/core/tdd.md
  - rules/core/design.md
  - rules/core/testing.md
  - rules/core/commit.md
  - <言語別 rules があれば追加>
prev_phase_summary: |                     # 直前フェーズの 1-3 行要約
  <decisions.jsonl から拾う or skip>
poc_results:                              # dev-spec フェーズ 5 が FEASIBILITY.md「PoC 結果」に記録した内容から抽出。FEASIBILITY.md が無い場合は省略
  - id: <POC_NEEDED id>
    recommended_approach: <結論>
dev_server:                                # review-product-readiness (Step 4.2d) 用。Web プロダクトでなければ省略 (null)
  url: <検出できた URL>
  start_command: <package.json の dev/start script>
```

抜粋ロジック:

- `phase_tasks`: TODO.md を Read して `### フェーズN:` から次フェーズ見出しまでを切り出し
- `design_overview` / `design_detail`: フェーズ名から推測した key term (例: 「認証」「ユーザー登録」「CI」「デプロイ」) で DESIGN / DETAIL_APP / DETAIL_INFRA を grep、ヒット節とその前後を抜粋。**抜粋は必須、全文フォールバックは禁止** (context ファイルは 1 フェーズにつき最大 4 検査 subagent がそれぞれ Read するため、全文だとコストが大きい)。抜粋の目安上限は 1 ファイルあたり 4KB、超える場合は該当節の見出し + 要約のみ残す。抜粋に加えて「このフェーズに関連しそうな DESIGN / DETAIL_APP / DETAIL_INFRA の見出し一覧」を必ず列挙し、抜粋に本文が無い見出しが必要になったら `design_overview_path` / `design_detail_app_path` / `design_detail_infra_path` を自分で Read する (メインループ・検査 subagent 共通。抜粋漏れを silent にしない)
- `related_source_files`: フェーズ名 / phase_tasks から推測したキーワードで Glob (`src/**/*<key>*`) + git diff で過去フェーズで触ったファイル
- `prev_phase_summary`: decisions.jsonl の直前 phase の `event_type: done` エントリ summary を引く
- `dev_server`: **`product_mode: cli` の場合は判定せず常に省略する** (dir 名の推定を行わない)。`webapp` / `unknown` の場合は Web プロダクト判定 (`apps/web/`, `apps/`, `web/`, `frontend/` 等のディレクトリ + `package.json` の `dev`/`start` script の有無) を使う
  - Web プロダクトでなければ `dev_server` を省略 (review-product-readiness は URL 不在で no-op、`ok: true` 素通り)
  - Web プロダクトの場合: `start_command` は `package.json` の `scripts.dev` (無ければ `scripts.start`) をそのまま使う。`url` は以下の順に推定する:
    ```bash
    rg -n 'port\s*:\s*\d+' vite.config.ts vite.config.js 2>/dev/null   # Vite の server.port 明示指定
    test -f next.config.js -o -f next.config.ts && echo "port=3000"    # Next.js デフォルト
    test -f vite.config.ts -o -f vite.config.js && echo "port=5173"    # Vite デフォルト (上のrgでヒット無ければ)
    ```
    **推定に確信が持てない場合 (上記いずれにも一致しない) は `dev_server` ごと省略する** (誤ったポートを渡すと review-product-readiness が `dev_server_unavailable` の偽陽性を報告し、self-fix loop が実装側で直しようのないエラーを無限に再試行することになるため)

review-adversarial は本ファイルを受け取らない (fresh context 監査のため、phase_name / phase_start_sha / docs_dir / dev_server / scratch_dir / output_path のみを直接渡す)。

