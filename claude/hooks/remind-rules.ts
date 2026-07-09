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
// 機械ゲート化できない項目 (外科的変更 / TDD 例外の明示) だけをリマインドする
const REMINDER = `<system-reminder>
[hook: remind-rules] 実装/修正系の指示を検知。依頼スコープを超えない (外科的変更: 隣接改善・dead code 削除は別ターンで合意)。TDD を適用しない判断 (typo 修正・宣言的 config 等) はその理由を出力で明示する。
実装・テスト実行・コミットに着手する前に現在のメインループのモデルを確認する。Fable/Opus 等の高コストモデルなら、機能単位の実装は Sonnet、テスト実行・コミット実行は Haiku のサブエージェントに委譲し (結果は SendMessage で親に報告させる)、メインは制御に専念する。
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
