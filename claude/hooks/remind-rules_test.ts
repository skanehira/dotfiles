import { assertEquals } from "jsr:@std/assert";
import {
  buildAdditionalContext,
  decideReminder,
  DOC_REMINDER,
  IMPL_REMINDER_FULL,
  IMPL_REMINDER_SHORT,
  isDocumentationPrompt,
} from "./remind-rules.ts";

Deno.test("decideReminder with impl prompt and no prior full reminder returns full", () => {
  assertEquals(decideReminder("バグを修正して", false), "full");
});

Deno.test("decideReminder with impl prompt after full reminder sent returns short", () => {
  assertEquals(decideReminder("続きを実装して", true), "short");
});

Deno.test("decideReminder with non-impl prompt returns null regardless of state", () => {
  assertEquals(decideReminder("この関数の仕組みを教えて", false), null);
  assertEquals(decideReminder("この関数の仕組みを教えて", true), null);
});

// 回帰: 2026-07-11 vime.nvim セッションで願望形 (〜したい) が検知漏れした実プロンプト
Deno.test("decideReminder with desire-form prompt (回避したい) returns full", () => {
  assertEquals(
    decideReminder(
      "vimeで一度日本語を有効にすると<C-r>キーマップが消されてしまうようなので、この問題を回避したい",
      false,
    ),
    "full",
  );
});

Deno.test("decideReminder with desire-form prompt (できるようにしたい) returns full", () => {
  assertEquals(
    decideReminder(
      "補完候補を選択しているときに、<C-g>だけじゃなくてEscでキャンセルできるようにしたい",
      false,
    ),
    "full",
  );
});

Deno.test("decideReminder with request-form prompt (できるようにして) returns full", () => {
  assertEquals(decideReminder("タブキーで補完を確定できるようにして", false), "full");
});

Deno.test("decideReminder with request-form prompt (てほしい) returns full", () => {
  assertEquals(decideReminder("ボタンの色を変えてほしい", false), "full");
});

Deno.test("isDocumentationPrompt detects document modification prompts", () => {
  const cases = [
    "設計書を修正して",
    "DESIGN.md に反映して",
    "README を更新して",
    "ドキュメントを改訂して",
    "仕様書に追記して",
  ];
  for (const prompt of cases) {
    assertEquals(isDocumentationPrompt(prompt), true, prompt);
  }
});

Deno.test("isDocumentationPrompt ignores read-only or question prompts about documents", () => {
  const cases = [
    "設計について教えて",
    "ドキュメントを読んで",
    "README はどこ?",
  ];
  for (const prompt of cases) {
    assertEquals(isDocumentationPrompt(prompt), false, prompt);
  }
});

Deno.test("buildAdditionalContext with first impl-only prompt returns full impl reminder", () => {
  assertEquals(
    buildAdditionalContext("バグを修正して", false),
    `<system-reminder>\n${IMPL_REMINDER_FULL}\n</system-reminder>`,
  );
});

Deno.test("buildAdditionalContext with impl-only prompt after full sent returns short impl reminder", () => {
  assertEquals(
    buildAdditionalContext("続きを実装して", true),
    `<system-reminder>\n${IMPL_REMINDER_SHORT}\n</system-reminder>`,
  );
});

Deno.test("buildAdditionalContext with first doc modification prompt concatenates full impl and doc reminders", () => {
  // 「修正して」は実装系パターンにもマッチするため、両リマインドが連結される
  assertEquals(
    buildAdditionalContext("設計書を修正して", false),
    `<system-reminder>\n${IMPL_REMINDER_FULL}\n\n${DOC_REMINDER}\n</system-reminder>`,
  );
});

Deno.test("buildAdditionalContext with doc modification prompt after full sent concatenates short impl and doc reminders", () => {
  assertEquals(
    buildAdditionalContext("設計書を修正して", true),
    `<system-reminder>\n${IMPL_REMINDER_SHORT}\n\n${DOC_REMINDER}\n</system-reminder>`,
  );
});

Deno.test("buildAdditionalContext with doc-only prompt returns doc reminder regardless of impl tier state", () => {
  // 「更新」は実装系パターンに含まれないため doc 単独。DOC リマインドは 2 段化しない
  assertEquals(
    buildAdditionalContext("README を更新して", false),
    `<system-reminder>\n${DOC_REMINDER}\n</system-reminder>`,
  );
  assertEquals(
    buildAdditionalContext("README を更新して", true),
    `<system-reminder>\n${DOC_REMINDER}\n</system-reminder>`,
  );
});

Deno.test("buildAdditionalContext with non-matching prompt returns null", () => {
  assertEquals(buildAdditionalContext("README はどこ?", false), null);
});
