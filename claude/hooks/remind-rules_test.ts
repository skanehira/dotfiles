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
