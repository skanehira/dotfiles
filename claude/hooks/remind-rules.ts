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

const REMINDER = `<system-reminder>
[hook: remind-rules] 実装/修正系の指示を検知しました。
着手前に以下を必ず実行してください:

1. **CLAUDE.md と rules を再確認**
   - @rules/core/tdd.md は交渉の余地なし (RED → GREEN → REFACTOR の順)
   - @rules/core/design.md / testing.md / commit.md にも目を通す
2. **TaskCreate で TDD ステップを宣言**
   - 「失敗テストを書く」「最小実装」「リファクタ + 緑確認」を独立タスクとして並べる
3. **「テストを先に書く」と明示宣言**
   - ターン冒頭で「TDD で進めます。まず ○○ のテストを書きます」と言う
4. **依頼スコープを超えない (外科的変更)**
   - 隣接コードの改善・dead code 削除・気付いた別バグの修正は別ターンで合意してから

これを無視して実装に入った場合、後で「TDD やった?」と聞かれたとき正直に「やってない」と答えることになります。
TDD を本当にやらない判断をするときは、その理由を明示してください (例: 1 行 typo 修正、宣言的な config 変更など)。
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
