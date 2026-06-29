#!/usr/bin/env -S deno run --allow-env --allow-read
export {};

/**
 * Stop hook。作業ループ終了前に CLAUDE.md / rules への遵守を Claude 自身に
 * セルフレビューさせる。
 *
 * 設計:
 * - 直前ターンで Edit/Write/NotebookEdit 等の編集系 tool を使っていなければ
 *   そもそも self-review 不要なので発火しない (調査/質問だけのターンは無音)
 * - 編集系を使っていれば、Stop を block して Claude にもう 1 ターン回させる
 * - 無限ループ防止: Claude が self-review を完了したマーカー
 *   `[self-review-done]` を assistant message 末尾に出した場合は block しない
 *
 * これにより「直前ターンで実装した → Stop → self-review プロンプトを受ける →
 * Claude が review してマーカー付きで応答 → 次の Stop は素通り」のサイクルが回る。
 */

type StopInput = {
  hook_event_name?: string;
  session_id?: string;
  transcript_path?: string;
  stop_hook_active?: boolean;
};

const EDIT_TOOLS = new Set([
  "Edit",
  "Write",
  "NotebookEdit",
]);

const REVIEW_DONE_MARKER = "[self-review-done]";

async function readTranscript(path: string): Promise<unknown[]> {
  try {
    const txt = await Deno.readTextFile(path);
    return txt
      .trim()
      .split("\n")
      .map((line) => {
        try {
          return JSON.parse(line);
        } catch {
          return null;
        }
      })
      .filter((x): x is Record<string, unknown> => x !== null);
  } catch {
    return [];
  }
}

/**
 * transcript の末尾から逆順に走査し、直近 user turn (= 最後にユーザが発言した位置)
 * 以降の assistant entries を集める。これが「直前ターン」とみなす。
 */
function lastAssistantTurnEntries(entries: unknown[]): unknown[] {
  let lastUserIdx = -1;
  for (let i = entries.length - 1; i >= 0; i--) {
    const e = entries[i] as { type?: string };
    if (e?.type === "user") {
      lastUserIdx = i;
      break;
    }
  }
  return entries.slice(lastUserIdx + 1);
}

function usedEditTools(entries: unknown[]): boolean {
  for (const e of entries) {
    const msg = (e as { message?: { content?: unknown } })?.message;
    const content = msg?.content;
    if (!Array.isArray(content)) continue;
    for (const item of content) {
      const it = item as { type?: string; name?: string };
      if (it?.type === "tool_use" && it?.name && EDIT_TOOLS.has(it.name)) {
        return true;
      }
    }
  }
  return false;
}

function hasReviewDoneMarker(entries: unknown[]): boolean {
  for (const e of entries) {
    const msg = (e as { message?: { content?: unknown } })?.message;
    const content = msg?.content;
    if (!Array.isArray(content)) continue;
    for (const item of content) {
      const it = item as { type?: string; text?: string };
      if (it?.type === "text" && typeof it?.text === "string" && it.text.includes(REVIEW_DONE_MARKER)) {
        return true;
      }
    }
  }
  return false;
}

const REVIEW_PROMPT = `<system-reminder>
[hook: self-review] 直前ターンで編集系 tool (Edit/Write/NotebookEdit) を使いました。
停止前に CLAUDE.md / rules に照らしてセルフレビューしてください。

チェックリスト:
- [ ] **TDD**: 失敗テストを先に書きましたか? 書いていなければ理由を明示するか、後付けでもテストを追加してください
- [ ] **最小実装**: 依頼スコープを超えた機能・抽象化・error handling を追加していませんか?
- [ ] **外科的変更**: 依頼にトレースできない隣接コードの改善・dead code 削除をしていませんか?
- [ ] **テスト緑**: 影響範囲のテストを実行して全部通っていますか? (まだなら今走らせる)
- [ ] **コミット規約**: コミットしたなら関心ごと分割、HEREDOC、Co-Authored-By を守っていますか?

各項目を 1 行で答えてください (例: 「TDD: 違反、後追いで test 追加済み」「最小実装: OK」)。
すべて確認できたら**ユーザに見える形で**結果を述べ、最後の行に \`${REVIEW_DONE_MARKER}\` というマーカーを付けてください。マーカーを付けるとこの hook は次回 block しません。

違反が見つかったら、停止せずに修正に戻ってください。
</system-reminder>`;

async function main() {
  let input: StopInput = {};
  try {
    input = await new Response(Deno.stdin.readable).json();
  } catch {
    return;
  }

  // stop_hook_active が true = この hook がトリガーした続行ターン。
  // 無限ループ防止のため、ここでは追加 block しない (Claude が判定を任される)。
  if (input.stop_hook_active) {
    return;
  }

  const path = input.transcript_path;
  if (!path) return;

  const entries = await readTranscript(path);
  const lastTurn = lastAssistantTurnEntries(entries);

  // 編集系を使っていなければ self-review 不要
  if (!usedEditTools(lastTurn)) return;

  // 既に self-review 完了マーカーが付いていれば素通り
  if (hasReviewDoneMarker(lastTurn)) return;

  const output = {
    decision: "block",
    reason: REVIEW_PROMPT,
  };
  console.log(JSON.stringify(output));
}

await main();
