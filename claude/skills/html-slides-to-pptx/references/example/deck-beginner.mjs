// beginner/index.html の SLIDES 配列を移植したデータ
import { C } from "./pptx-theme.mjs";

export const deck = {
  id: "beginner",
  levelTag: "初級",
  title: "Claude Code 研修 初級",
  duration: "HANDS-ON ・ 4h",
  level: C.green,
};

export const slides = [
  {
    type: "hero",
    title: 'Claude Code 研修 <span class="accent">初級</span>',
    sub: "AIコーディングエージェントの基本ワークフローを、半日で「一人で回せる」ように。",
    meta: ["半日 ・ 約4時間", "ハンズオン形式", "AIコーディング未経験者向け"],
  },
  {
    prompt: '"このコースのゴールを教えて"',
    title: "今日の到達点 ── <em>一人で回せる</em> + <em>本番URLで動く</em>",
    body: [
      {
        k: "cards",
        cols: 2,
        items: [
          {
            num: "GOAL 1",
            title: "Explore → Plan → Code → Commit を一人で完走",
            body: "<p>バグ修正・小機能追加を Claude Code に任せ、自分は「計画の承認」と「結果の検証」に集中する開発スタイルを体得します。</p>",
          },
          {
            num: "GOAL 2",
            title: "AIに頼んで本番デプロイ",
            body: "<p>「Cloudflareにデプロイして」の一言で、DB作成からデプロイまでの複数ステップをエージェントに完走させます。</p>",
          },
        ],
      },
      { k: "pass", text: "修了成果物 = 本番URLで動くチームタスクボード + 自分のコミット履歴" },
    ],
  },
  {
    prompt: '"最終的に何を作るの?"',
    title: "題材はひとつ ── <em>チームタスクボード</em>を3コースで育てる",
    topic: "題材アプリとロードマップ",
    time: "0:00–0:10",
    body: [
      {
        k: "cards",
        cols: 3,
        items: [
          {
            num: "初級 ── ★",
            numColor: C.green,
            highlight: true,
            title: "完了フラグ",
            body: "<p>チェックで完了・絞り込み表示。1テーブル1カラム+トグルUI。</p>",
          },
          {
            num: "中級 ── ★★",
            numColor: C.cyan,
            title: "タグ機能",
            body: "<p>担当者/分類タグと絞り込み。新テーブル（多対多）+migration+API+UI。</p>",
          },
          {
            num: "上級 ── ★★★",
            numColor: C.magenta,
            title: "繰り返しタスク",
            body: "<p>毎日/毎週/毎月、完了時に次回を自動生成。月末・うるう年の境界処理。</p>",
          },
        ],
      },
      {
        k: "panel",
        text: '修了時に残るのは、自分のCloudflareで動く<b>チームタスクボード</b>と、 それを安全に育て続けられる<b>ハーネス付きリポジトリ</b>。 コースが進むほど機能は複雑になる ── 複雑なほど「ハーネスが効いている」感覚が強くなる。',
      },
    ],
  },
  {
    prompt: '"環境をチェックして"',
    title: "はじめる前に ── 事前準備チェック",
    topic: "事前準備",
    time: "0:00–0:10",
    body: [
      {
        k: "term",
        title: "preflight-check",
        lines: [
          { t: "ok", s: "✓ Claude Pro/Max アカウント（または会社支給アカウント）" },
          { t: "ok", s: "✓ Cloudflare アカウント（無料枠でOK）" },
          { t: "ok", s: "✓ GitHub アカウント" },
          { t: "ok", s: "✓ Node.js / pnpm / git / VS Code" },
          { t: "ok", s: "✓ wrangler login 済み" },
          { t: "dim", s: "" },
          { t: "warn", s: "! 未完了の項目がある人は今すぐ挙手 ── 始まる前に一緒に解決します" },
        ],
      },
    ],
  },
  {
    prompt: '"本日の流れを教えて"',
    title: "4時間の地図 ── 画面下のバーが常に現在地",
    topic: "本日の流れ",
    time: "0:00–0:10",
    body: [
      {
        k: "timetable",
        rows: [
          { time: "0:10–0:30", no: "T1", topic: "AIコーディングエージェントとは", desc: "チャットAIとの違いを見る（講師デモ）" },
          { time: "0:30–0:45", no: "T2", topic: "エージェントループの仕組み", desc: "ツール呼び出しログを読む（講師デモ）" },
          { time: "0:45–1:05", no: "T3", topic: "インストールと初回起動", desc: "各自インストール → 最初のプロンプト" },
          { time: "1:05–1:50", no: "T4", topic: "Explore → Plan → Code → Commit", desc: "仕込まれたバグをテストgreenまで直す" },
          { time: "1:50–2:00", topic: "休憩", break: true },
          { time: "2:00–2:15", no: "T5", topic: "コンテキスト管理", desc: "/context と /compact を体感する" },
          { time: "2:15–2:35", no: "T6", topic: "CLAUDE.md", desc: "プロジェクトの記憶を書いて検証する" },
          { time: "2:35–2:50", no: "T7", topic: "Subagents / Skills / MCP / Hooks 概観", desc: "中級への予告編（講師デモ）" },
          { time: "2:50–3:50", no: "T8", topic: "総合ハンズオン", desc: "機能追加 → 本番デプロイまで完走" },
          { time: "3:50–4:00", topic: "クロージング", break: true },
        ],
      },
    ],
  },
  {
    prompt: '"このバグを直して"',
    title: "チャットAIと<em>エージェント</em>は何が違う?",
    badge: "demo",
    topic: "T1 ── AIコーディングエージェントとは",
    time: "0:10–0:30",
    body: [
      {
        k: "cards",
        cols: 2,
        items: [
          {
            num: "CHAT",
            title: "チャットAI",
            list: [
              "貼られたコードしか見えない",
              "「こう直すといいですよ」と提案を返す",
              "実行するのはあなた",
              "動くかどうか検証するのもあなた",
            ],
          },
          {
            num: "AGENT",
            title: "Claude Code",
            list: [
              "リポジトリを自分で探索する",
              "ファイルを直接編集する",
              "テストを自分で実行する",
              "結果を見て自分で直す",
            ],
          },
        ],
      },
      { k: "pass", text: "チャットとエージェントの違いを1文で言える" },
    ],
  },
  {
    prompt: '"落ちているテストの原因を直して"',
    title: "エージェントループ ── <em>収集 → 行動 → 検証</em>",
    badge: "demo",
    topic: "T2 ── エージェントループの仕組み",
    time: "0:30–0:45",
    body: [
      {
        k: "term",
        title: "claude ── ツール呼び出しログ",
        lines: [
          { t: "u", s: "落ちているテストの原因を直して" },
          { t: "a", s: "Bash(pnpm test)                        # 検証 ── まず現状を見る" },
          { t: "ng", s: "✗ 1 failed ── tasks.test.ts" },
          { t: "a", s: "Read(src/server/routes/tasks.ts)       # 収集 ── コードを読む" },
          { t: "a", s: "Edit(src/server/routes/tasks.ts)       # 行動 ── 直す" },
          { t: "a", s: "Bash(pnpm test)                        # 検証 ── もう一度確かめる" },
          { t: "ok", s: "✓ 12 passed (12)" },
          { t: "dim", s: "ループは「検証が通るまで」回る ── だからテストがあるほどAIは強くなる" },
        ],
      },
      { k: "pass", text: "ログの中の「収集・行動・検証」を指し示せる" },
    ],
  },
  {
    prompt: '"このプロジェクトの構成を説明して"',
    title: "インストールして、最初の一言",
    badge: "hands-on",
    topic: "T3 ── インストールと初回起動",
    time: "0:45–1:05",
    body: [
      {
        k: "term",
        title: "terminal",
        lines: [
          { t: "u", s: "npm install -g @anthropic-ai/claude-code" },
          { t: "u", s: "git clone <題材リポジトリのURL> && cd <リポジトリ名>" },
          { t: "u", s: "claude" },
          { t: "a", s: "Welcome to Claude Code!" },
          { t: "u", s: "このプロジェクトの構成を説明して" },
          { t: "a", s: "React 19 + Hono + Cloudflare D1 のチームタスクボードです。src/front が SPA、…" },
        ],
      },
      { k: "pass", text: "プロジェクト概要の説明が返ってくる" },
    ],
  },
  {
    prompt: '"テストをgreenにして"',
    title: "基本ワークフロー ── <em>Explore → Plan → Code → Commit</em>",
    badge: "hands-on",
    topic: "T4 ── 基本ワークフロー",
    time: "1:05–1:50",
    body: [
      {
        k: "cards",
        cols: 2,
        items: [
          {
            num: "1. EXPLORE",
            title: "探索させる",
            body: "<p>「なぜこのテストが落ちているか調べて」。まず原因をAIに探索させ、思い込みで直させない。</p>",
          },
          {
            num: "2. PLAN",
            title: "Plan Mode で計画を承認",
            body: "<p>Shift+Tab で Plan Mode に切り替え。修正方針を先に出させ、納得してから実行に移す。</p>",
          },
          {
            num: "3. CODE",
            title: "実装と検証はエージェント",
            body: "<p>編集もテスト実行もAIの仕事。あなたはdiffとテスト結果を見る。</p>",
          },
          {
            num: "4. COMMIT",
            title: "diffを確認してコミット",
            body: "<p>「コミットして」で完了。何をコミットしたか自分の言葉で説明できること。</p>",
          },
        ],
      },
      { k: "pass", text: "テスト green + コミット1つ" },
    ],
  },
  {
    prompt: "/context",
    title: "コンテキストは<em>有限</em> ── 長い会話は劣化する",
    badge: "hands-on",
    topic: "T5 ── コンテキスト管理",
    time: "2:00–2:15",
    body: [
      {
        k: "cols",
        items: [
          {
            k: "term",
            title: "claude",
            lines: [
              { t: "u", s: "/context" },
              { t: "warn", s: "▮▮▮▮▮▮▮▯▯▯ 68% used" },
              { t: "u", s: "/compact" },
              { t: "a", s: "ここまでの会話を要約して圧縮しました" },
              { t: "u", s: "/context" },
              { t: "ok", s: "▮▮▮▯▯▯▯▯▯▯ 31% used" },
            ],
          },
          {
            k: "card",
            title: "使い分けの目安",
            list: [
              '<span class="mono">/context</span> ── 今どれだけ使っているか見る',
              '<span class="mono">/compact</span> ── 大きな作業の前に圧縮する',
              '<span class="mono">/clear</span> ── 別のタスクに移るときはゼロから',
            ],
            note: "古い指示ほど薄まる。「覚えているはず」を疑うのが上達の第一歩。",
          },
        ],
      },
      { k: "pass", text: "使用量の増減を自分の目で確認した" },
    ],
  },
  {
    prompt: '"コミットして"',
    title: "CLAUDE.md ── プロジェクトの<em>記憶</em>を書く",
    badge: "hands-on",
    topic: "T6 ── CLAUDE.md",
    time: "2:15–2:35",
    body: [
      {
        k: "cols",
        items: [
          {
            k: "term",
            title: "CLAUDE.md",
            lines: [
              { t: "dim", s: "# CLAUDE.md" },
              { t: "a", s: "- コミットメッセージは日本語で書く" },
              { t: "a", s: "- テストは pnpm test で実行する" },
              { t: "a", s: "- UIの文言は「です・ます」調にする" },
            ],
          },
          {
            k: "card",
            title: "毎回説明していた約束事を、一度だけ書く",
            list: [
              "セッションを跨いで効く ── 明日も同じ約束を守る",
              "リポジトリにコミットすれば<b>チーム全員</b>のClaude Codeが従う",
              "書いたら検証 ── 同じ依頼を出して出力が変わるか確かめる",
            ],
          },
        ],
      },
      { k: "pass", text: "指示を書く前と後で、コミットメッセージの言語が変わった" },
    ],
  },
  {
    prompt: "--help",
    title: "この先の世界 ── 中級への予告編",
    badge: "demo",
    topic: "T7 ── Subagents / Skills / MCP / Hooks 概観",
    time: "2:35–2:50",
    body: [
      {
        k: "cards",
        cols: 2,
        items: [
          {
            num: "SUBAGENTS",
            title: "調査を隔離して委任",
            body: "<p>大きな調査を別コンテキストのエージェントに任せ、メインの会話を汚さない。</p>",
          },
          {
            num: "SKILLS",
            title: "定型手順を指示書に",
            body: "<p>チームの手順を再利用可能なスキルとして配布し、誰がやっても同じ品質に。</p>",
          },
          {
            num: "MCP",
            title: "外部ツールをAIの手に",
            body: "<p>ブラウザや外部ドキュメントをAI自身が操作して、検証まで任せられる。</p>",
          },
          {
            num: "HOOKS",
            title: "危険な操作を機械的にブロック",
            body: "<p>「気をつけて」ではなくコードで禁止する。守らせたいことはルールではなく構造に。</p>",
          },
        ],
      },
      { k: "pass", text: "4つの機能をそれぞれ1文で説明できる" },
    ],
  },
  {
    prompt: '"Cloudflareにデプロイして"',
    title: "総合ハンズオン ── 機能追加から<em>本番デプロイ</em>まで",
    badge: "hands-on",
    topic: "T8 ── 総合ハンズオン",
    time: "2:50–3:50",
    body: [
      {
        k: "cols",
        items: [
          {
            k: "card",
            title: "やること",
            list: [
              "<b>STEP 1</b> ── 完了フラグ（チェックで完了・絞り込み表示）を T4 のワークフローで完走",
              "<b>STEP 2</b> ── 「Cloudflareにデプロイして」と依頼する",
              "<b>STEP 3</b> ── 発行された workers.dev のURLをスマホで開いて動作確認",
            ],
            note: "早く終わった人には追加課題があります（難易度別に2〜3件）。",
          },
          {
            k: "term",
            title: "claude ── デプロイの中でエージェントがやっていること",
            lines: [
              { t: "u", s: "Cloudflareにデプロイして" },
              { t: "a", s: "Bash(wrangler d1 create taskboard-db) # DBを作成" },
              { t: "a", s: "Edit(wrangler.jsonc)                  # database_id を反映" },
              { t: "a", s: "Bash(wrangler d1 migrations apply …)  # スキーマを適用" },
              { t: "a", s: "Bash(wrangler deploy)                 # デプロイ" },
              { t: "ok", s: "✨ https://taskboard.<あなた>.workers.dev" },
            ],
          },
        ],
      },
      { k: "pass", text: "本番URLでアプリが動く" },
    ],
  },
  {
    prompt: '"受講前後を比較して"',
    title: "身につけると<em>どうなれるか</em>",
    topic: "クロージング",
    time: "3:50–4:00",
    body: [
      {
        k: "beforeAfter",
        pairs: [
          ["AIコーディングは「チャットにコードを貼って聞く」もの", "エージェントがファイルを読み・編集し・テストする開発スタイルで働ける"],
          ["バグ修正・小機能追加は全部自分の手を動かす", "日常タスクをAIに任せ、計画の承認と結果の検証に集中できる"],
          ["デプロイは手順書を見ながら1ステップずつ", "「デプロイして」の一言で複数ステップを完走させられる"],
          ["AIの出力が正しいか判断できず不安", "テストとdiffで機械的に検証する習慣がある"],
          ["プロジェクトの約束事を毎回説明", "CLAUDE.mdに書いて一度で済ませられる"],
        ],
      },
    ],
  },
  {
    prompt: '"次は?"',
    title: "ここから先は「仕組みを<em>作る</em>」側へ",
    topic: "クロージング",
    time: "3:50–4:00",
    body: [
      { k: "courseMap", current: "beginner" },
      {
        k: "panel",
        text: "中級では今日デモで見た <b>Subagents / Skills / MCP / Hooks</b> を自分の手で作ります。 題材は今日デプロイしたチームタスクボードの続き（★★のタグ機能）── 忘れないうちにまた触っておいてください。",
      },
    ],
  },
];
