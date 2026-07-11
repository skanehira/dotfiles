#!/usr/bin/env -S deno run --allow-env --allow-read
export {};

/**
 * UserPromptSubmit hook。
 *
 * ユーザのプロンプトに「実装/修正/追加/リファクタ等」のシグナルを含むなら、
 * CLAUDE.md の実装系ルール (TDD / 最小実装 / 外科的変更 等) を <system-reminder>
 * として再注入する。
 *
 * これは「CLAUDE.md に書いてあるのに守られない」問題への機械的担保。
 * Claude が prompt を読む前に hook が必ず実行され、stdout に出した
 * additionalContext が Claude のコンテキストに挿入される。
 *
 * 実装系でない (調査・質問・確認) プロンプトには発火しない (ノイズ削減)。
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

// TDD の手順は tdd-guard hook が tool call レベルで強制するため、ここでは
// 機械ゲート化できない項目 (トリアージ / rules の遅延 Read / 外科的変更 /
// TDD 例外の明示) だけをリマインドする。rules/core/*.md は CLAUDE.md から
// 即時展開されない (遅延参照) ため、この Read 指示が実質の読込トリガー。
const REMINDER = `<system-reminder>
[hook: remind-rules] 実装/修正系の指示を検知。
1. トリアージ: 着手前にタスクを分解し、ユニットごとのモデル割当 (CLAUDE.md「オーケストレーションとモデル階層」の 3 軸判定: 難易度/コンテキスト連続性/並列性) を 1 行で出力する。セッションが最上位 tier (Fable/Mythos 級) で実装作業が支配的なら、着手前に /model sonnet (または opus) への切替をユーザに提案する。
2. rules: このセッションで未読なら ~/.claude/rules/core/ の tdd.md / design.md / testing.md を Read してから着手する (読了済みなら再読不要)。
3. 外科的変更: 依頼スコープを超えない (隣接改善・dead code 削除は別ターンで合意)。TDD を適用しない判断 (typo 修正・宣言的 config 等) はその理由を出力で明示する。
4. 委譲: 実装はメインループ直営 (逐次実装のサブエージェント委譲は禁止。委譲は並列 fan-out と巨大出力の隔離のみ、fan-out 時は難易度に応じ model: sonnet/opus を明示)。テスト実行 (E2E 等の巨大出力のみ)・コミット実行は Haiku に委譲する (コミットメッセージは親が起草し、Haiku には実行だけさせる)。
</system-reminder>`;

async function main() {
  let input: UserPromptInput = {};
  try {
    input = await new Response(Deno.stdin.readable).json();
  } catch {
    return;
  }
  const prompt = input.prompt ?? "";
  if (!isImplementationPrompt(prompt)) {
    return;
  }

  const output = {
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: REMINDER,
    },
  };
  console.log(JSON.stringify(output));
}

await main();
