import { assertEquals } from "jsr:@std/assert";
import { decideReminder } from "./remind-rules.ts";

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
