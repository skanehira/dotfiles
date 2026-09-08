import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  GENERATED_MARKER,
  parseSubagent,
  toCodexToml,
  toOpencodeMarkdown,
} from "./subagent-format.ts";


/** frontmatter と body を差し替えられるフィクスチャ。既定は実正本に近い形 */
function subagentMarkdown(
  overrides: { frontmatter?: string; body?: string } = {},
): string {
  const frontmatter = overrides.frontmatter ??
    `name: review-impl
description: 実装差分の統合レビュワー。修正は行わない。
tools: Read, Grep, Glob, Bash, Write
context: fork
model: opus`;
  const body = overrides.body ??
    "# review-impl\n\n実装者と**別コンテキスト**で実装差分を検査する。\n";
  return `---\n${frontmatter}\n---\n\n${body}`;
}

Deno.test("parseSubagent_with_blank_lines_and_padded_values_splits_frontmatter_and_body", () => {
  const markdown = subagentMarkdown({
    frontmatter: "name:   review-impl  \n\ndescription: 統合レビュワー\n折り返しだけの行\ncontext: fork",
  });
  assertEquals(parseSubagent(markdown), {
    frontmatter: {
      name: "review-impl",
      description: "統合レビュワー",
      context: "fork",
    },
    body: "# review-impl\n\n実装者と**別コンテキスト**で実装差分を検査する。\n",
  });
});

Deno.test("parseSubagent_without_frontmatter_throws_with_the_offending_head", () => {
  assertThrows(
    () => parseSubagent("# no frontmatter\n"),
    Error,
    "frontmatter が見つかりません: # no frontmatter",
  );
});

Deno.test("toCodexToml_emits_only_name_description_and_instructions_dropping_tools_model_and_context", () => {
  assertEquals(
    toCodexToml(parseSubagent(subagentMarkdown())),
    `${GENERATED_MARKER}
name = "review-impl"
description = "実装差分の統合レビュワー。修正は行わない。"
developer_instructions = '''
# review-impl

実装者と**別コンテキスト**で実装差分を検査する。
'''
`,
  );
});

Deno.test("toOpencodeMarkdown_emits_only_description_and_mode_dropping_tools_model_and_context", () => {
  assertEquals(
    toOpencodeMarkdown(parseSubagent(subagentMarkdown())),
    `---
${GENERATED_MARKER}
description: 実装差分の統合レビュワー。修正は行わない。
mode: subagent
---

# review-impl

実装者と**別コンテキスト**で実装差分を検査する。
`,
  );
});

Deno.test("toCodexToml_escapes_quote_and_backslash_in_description", () => {
  const markdown = subagentMarkdown({
    frontmatter: 'name: q\ndescription: "引用" と \\ を含む',
    body: "body\n",
  });
  assertEquals(
    toCodexToml(parseSubagent(markdown)),
    `${GENERATED_MARKER}
name = "q"
description = "\\"引用\\" と \\\\ を含む"
developer_instructions = '''
body
'''
`,
  );
});

for (
  const { target, render, expected } of [
    {
      target: "codex",
      render: toCodexToml,
      expected: `${GENERATED_MARKER}\nname = "q"\ndescription = "d"\ndeveloper_instructions = '''\n改行で終わらない本文\n'''\n`,
    },
    {
      target: "opencode",
      render: toOpencodeMarkdown,
      expected: `---\n${GENERATED_MARKER}\ndescription: d\nmode: subagent\n---\n\n改行で終わらない本文\n`,
    },
  ]
) {
  Deno.test(`${render.name}_with_body_missing_trailing_newline_appends_one_for_${target}`, () => {
    const markdown = subagentMarkdown({
      frontmatter: "name: q\ndescription: d",
      body: "改行で終わらない本文",
    });
    assertEquals(render(parseSubagent(markdown)), expected);
  });
}

Deno.test("toCodexToml_without_name_throws", () => {
  assertThrows(
    () => toCodexToml(parseSubagent(subagentMarkdown({ frontmatter: "description: d" }))),
    Error,
    "frontmatter に name がありません",
  );
});

Deno.test("toOpencodeMarkdown_without_description_throws", () => {
  assertThrows(
    () => toOpencodeMarkdown(parseSubagent(subagentMarkdown({ frontmatter: "name: q" }))),
    Error,
    "frontmatter に description がありません",
  );
});

Deno.test("toCodexToml_with_triple_quote_in_body_throws_instead_of_emitting_broken_toml", () => {
  assertThrows(
    () => toCodexToml(parseSubagent(subagentMarkdown({ body: "区切り ''' を含む本文\n" }))),
    Error,
    "review-impl: 本文に ''' が含まれるため TOML の literal string に入れられません",
  );
});
