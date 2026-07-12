#!/usr/bin/env -S deno run --allow-env --allow-read --allow-write

/**
 * UserPromptSubmit hook。
 *
 * ユーザのプロンプトに「実装/修正/追加/リファクタ等」のシグナルを含むなら、
 * CLAUDE.md の実装系ルール (トリアージ / rules の遅延 Read / 外科的変更 等) を
 * <system-reminder> として再注入する。ドキュメント修正系のシグナルを含むなら、
 * documentation.md の整合性パス (依拠事実の再検証 / 閉包チェック / 全文書き直し)
 * をリマインドする。両方にマッチした場合は両方を連結して注入する。
 *
 * これは「CLAUDE.md に書いてあるのに守られない」問題への機械的担保。
 * Claude が prompt を読む前に hook が必ず実行され、stdout に出した
 * additionalContext が Claude のコンテキストに挿入される。
 *
 * 反復注入コストを抑えるため実装系リマインドは 2 段構成: セッション初回の
 * 実装系プロンプトにはフル版、以降は短縮版を注入する (送信済みかは
 * ~/.claude/remind-rules/<session_id> のマーカーファイルで判定)。compaction で
 * フル版が要約に呑まれた場合も短縮版のままになるのは既知の制限 (短縮版が
 * CLAUDE.md の該当セクションを指すので実害小)。ドキュメント系リマインドは
 * 発火頻度が低く手順チェックリストとしての価値が編集の瞬間にあるため 2 段化しない。
 *
 * 読み取り・質問・確認系のプロンプトには発火しない (ノイズ削減)。
 */

type UserPromptInput = {
  hook_event_name?: string;
  session_id?: string;
  cwd?: string;
  prompt?: string;
};

// 実装/修正系シグナル。日本語/英語両対応。誤検知より検知漏れを避ける方針で広め。
const IMPL_PATTERNS = [
  /実装(し|する|して)/,
  /修正(し|する|して)/,
  /直[しすせ]/,
  /追加(し|する|して)/,
  /作(っ|る|って|成)/,
  /書[いきく]/,
  /対応(し|する|して)/,
  /リファクタ/,
  /改善(し|する|して)/,
  /変更(し|する|して)/,
  /削除(し|する|して)/,
  /置(き|き換|換)/,
  // 願望・依頼形 (任意動詞)。動詞固定リストでは「回避したい」「できるようにしたい」
  // のような依頼を拾えず検知漏れした (2026-07-11 vime.nvim セッションで実測)
  /したい/,
  /てほしい/,
  /てください/,
  /できるように/,
  /\bfix\b/i,
  /\bimplement/i,
  /\bcreate\b/i,
  /\badd\b/i,
  /\brefactor/i,
  /\bedit\b/i,
];

function isImplementationPrompt(prompt: string): boolean {
  return IMPL_PATTERNS.some((re) => re.test(prompt));
}

// ドキュメント修正系は「文書を指す名詞 × 修正系動詞」の両方を要求する。
// 名詞だけ (「README はどこ?」) や読み取り動詞 (「ドキュメントを読んで」) では発火させない。
const DOC_TARGET_PATTERNS = [
  /設計書/,
  /仕様書/,
  /手順書/,
  /ドキュメント/,
  /文書/,
  /README/i,
  /\.md\b/i,
  /\bdocs?\b/i,
];

const DOC_ACTION_PATTERNS = [
  /修正(し|する|して)/,
  /更新(し|する|して)/,
  /反映(し|する|して)/,
  /改訂(し|する|して)/,
  /追記(し|する|して)/,
  /加筆/,
  /書き(直|換|加え)/,
  /書いて/,
  /作(っ|る|って|成)/,
  /まとめ(て|る)/,
  /リライト/,
  /\bupdate\b/i,
  /\brevise\b/i,
  /\brewrite\b/i,
];

export function isDocumentationPrompt(prompt: string): boolean {
  return DOC_TARGET_PATTERNS.some((re) => re.test(prompt)) &&
    DOC_ACTION_PATTERNS.some((re) => re.test(prompt));
}

// TDD の手順は tdd-guard hook が tool call レベルで強制するため、ここでは
// 機械ゲート化できない項目 (トリアージ / rules の遅延 Read / 外科的変更 /
// TDD 例外の明示) だけをリマインドする。rules/core/*.md は CLAUDE.md から
// 即時展開されない (遅延参照) ため、この Read 指示が実質の読込トリガー。
export const IMPL_REMINDER_FULL =
  `[hook: remind-rules] 実装/修正系の指示を検知。
1. トリアージ: 着手前にタスクを分解し、ユニットごとのモデル割当 (CLAUDE.md「オーケストレーションとモデル階層」の 3 軸判定: 難易度/コンテキスト連続性/並列性) を 1 行で出力する。セッションが最上位 tier (Fable/Mythos 級) で実装作業が支配的なら、着手前に /model sonnet (または opus) への切替をユーザに提案する。
2. rules: このセッションで未読なら ~/.claude/rules/core/ の tdd.md / design.md / testing.md を Read してから着手する (読了済みなら再読不要)。
3. 外科的変更: 依頼スコープを超えない (隣接改善・dead code 削除は別ターンで合意)。TDD を適用しない判断 (typo 修正・宣言的 config 等) はその理由を出力で明示する。
4. 委譲: 実装はメインループ直営 (逐次実装のサブエージェント委譲は禁止。委譲は並列 fan-out と巨大出力の隔離のみ、fan-out 時は難易度に応じ model: sonnet/opus を明示し、実装系なら指示文に rules の Read 指示を含める)。テスト実行 (E2E 等の巨大出力のみ)・コミット実行は Haiku に委譲する (コミットメッセージは親が起草し、Haiku には実行だけさせる)。`;

// 2 回目以降: フル版の要点への短いポインタだけ再注入する (反復コスト削減)。
export const IMPL_REMINDER_SHORT =
  `[hook: remind-rules] 実装/修正系の指示を検知 (詳細は本セッション初回のフル版リマインダと CLAUDE.md「オーケストレーションとモデル階層」)。トリアージ (モデル割当 1 行明示・rules 未読なら Read) / 外科的変更 (TDD 例外は理由明示) / 委譲は並列 fan-out と巨大出力の隔離のみ (テスト・コミット実行は Haiku)。`;

export const DOC_REMINDER =
  `[hook: remind-rules] ドキュメント修正系の指示を検知しました。
着手前に:
1. 依拠事実の再検証 — 文書が前提とする実環境 (設定・CI・コマンド) を rg で確認 (過去調査の使い回し禁止)
2. 種別とフォーマット確認 — 文書冒頭の種別宣言と、型別規範 (rules/core/references/doc-formats/) への適合を確認してから書く
3. 概念の追加・削除・置換を含むなら、局所 Edit でなく全文を読み直して書き直す
編集後に:
4. 固有名の閉包チェック — 新出の用語・コマンド・ファイルに定義・生成者・消費者を書いたか。削除した概念の参照残骸を rg で掃いたか
5. 大きめの改訂なら /utility-doc-audit で fresh context の監査を実行する
詳細 → @rules/core/documentation.md`;

export type ReminderTier = "full" | "short";

export function decideReminder(
  prompt: string,
  fullAlreadySent: boolean,
): ReminderTier | null {
  if (!isImplementationPrompt(prompt)) {
    return null;
  }
  return fullAlreadySent ? "short" : "full";
}

export function buildAdditionalContext(
  prompt: string,
  fullAlreadySent: boolean,
): string | null {
  const parts: string[] = [];
  const tier = decideReminder(prompt, fullAlreadySent);
  if (tier === "full") {
    parts.push(IMPL_REMINDER_FULL);
  } else if (tier === "short") {
    parts.push(IMPL_REMINDER_SHORT);
  }
  if (isDocumentationPrompt(prompt)) {
    parts.push(DOC_REMINDER);
  }
  if (parts.length === 0) {
    return null;
  }
  return `<system-reminder>\n${parts.join("\n\n")}\n</system-reminder>`;
}

function markerPath(sessionId: string): string {
  const home = Deno.env.get("HOME") ?? "/tmp";
  return `${home}/.claude/remind-rules/${sessionId}`;
}

async function isFullSent(sessionId: string | undefined): Promise<boolean> {
  if (!sessionId) {
    return false;
  }
  try {
    await Deno.stat(markerPath(sessionId));
    return true;
  } catch {
    return false;
  }
}

async function markFullSent(sessionId: string | undefined): Promise<void> {
  if (!sessionId) {
    return;
  }
  const path = markerPath(sessionId);
  try {
    await Deno.mkdir(path.substring(0, path.lastIndexOf("/")), {
      recursive: true,
    });
    await Deno.writeTextFile(path, "");
  } catch {
    // マーカー書込失敗時は次回もフル版が出るだけなので握りつぶす
  }
}

async function main() {
  let input: UserPromptInput = {};
  try {
    input = await new Response(Deno.stdin.readable).json();
  } catch {
    return;
  }
  const prompt = input.prompt ?? "";
  const fullAlreadySent = await isFullSent(input.session_id);
  const additionalContext = buildAdditionalContext(prompt, fullAlreadySent);
  if (additionalContext === null) {
    return;
  }
  if (decideReminder(prompt, fullAlreadySent) === "full") {
    await markFullSent(input.session_id);
  }

  const output = {
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext,
    },
  };
  console.log(JSON.stringify(output));
}

if (import.meta.main) {
  await main();
}
