import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { parse as parseYaml } from "jsr:@std/yaml@1";
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

Deno.test("toCodexToml_with_body_missing_trailing_newline_appends_one", () => {
  const markdown = subagentMarkdown({
    frontmatter: "name: q\ndescription: d",
    body: "改行で終わらない本文",
  });
  assertEquals(
    toCodexToml(parseSubagent(markdown)),
    `${GENERATED_MARKER}\nname = "q"\ndescription = "d"\ndeveloper_instructions = '''\n改行で終わらない本文\n'''\n`,
  );
});

Deno.test("toCodexToml_without_name_throws", () => {
  assertThrows(
    () => toCodexToml(parseSubagent(subagentMarkdown({ frontmatter: "description: d" }))),
    Error,
    "frontmatter に name がありません",
  );
});

Deno.test("toCodexToml_without_description_throws", () => {
  assertThrows(
    () => toCodexToml(parseSubagent(subagentMarkdown({ frontmatter: "name: q" }))),
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

Deno.test("toOpencodeMarkdown_emits_only_description_and_mode_dropping_name_tools_model_and_context", () => {
  assertEquals(
    toOpencodeMarkdown(parseSubagent(subagentMarkdown())),
    `---
${GENERATED_MARKER}
description: "実装差分の統合レビュワー。修正は行わない。"
mode: subagent
---

# review-impl

実装者と**別コンテキスト**で実装差分を検査する。
`,
  );
});

Deno.test("toOpencodeMarkdown_quotes_a_description_containing_a_colon_so_the_yaml_stays_one_key", () => {
  const markdown = subagentMarkdown({
    frontmatter: "name: q\ndescription: dev-impl から起動される: 実装専用 agent",
    body: "body\n",
  });
  assertEquals(
    toOpencodeMarkdown(parseSubagent(markdown)),
    `---\n${GENERATED_MARKER}\ndescription: "dev-impl から起動される: 実装専用 agent"\nmode: subagent\n---\n\nbody\n`,
  );
});

Deno.test("toOpencodeMarkdown_frontmatter_parses_back_as_yaml_with_description_and_mode_only", () => {
  // 生成した文字列を OpenCode 側と同じく YAML として読み直す。上のテストは実装が
  // その文字列を出すことしか見ておらず、YAML 上で 1 キーに保たれるかは検査できない
  const description = "dev-impl から起動される: 実装専用 agent。mode: implement で新規実装";
  const markdown = subagentMarkdown({
    frontmatter: `name: q\ndescription: ${description}`,
    body: "body\n",
  });

  const generated = toOpencodeMarkdown(parseSubagent(markdown));
  const frontmatter = generated.match(/^---\n([\s\S]*?)\n---\n/);
  assertEquals(frontmatter !== null, true);
  assertEquals(parseYaml(frontmatter![1]), { description, mode: "subagent" });
});

Deno.test("toOpencodeMarkdown_escapes_quote_and_backslash_in_description", () => {
  const markdown = subagentMarkdown({
    frontmatter: 'name: q\ndescription: "引用" と \\ を含む',
    body: "body\n",
  });
  assertEquals(
    toOpencodeMarkdown(parseSubagent(markdown)),
    `---\n${GENERATED_MARKER}\ndescription: "\\"引用\\" と \\\\ を含む"\nmode: subagent\n---\n\nbody\n`,
  );
});

Deno.test("toOpencodeMarkdown_with_body_missing_trailing_newline_appends_one", () => {
  const markdown = subagentMarkdown({
    frontmatter: "name: q\ndescription: d",
    body: "改行で終わらない本文",
  });
  assertEquals(
    toOpencodeMarkdown(parseSubagent(markdown)),
    `---\n${GENERATED_MARKER}\ndescription: "d"\nmode: subagent\n---\n\n改行で終わらない本文\n`,
  );
});

Deno.test("toOpencodeMarkdown_without_description_throws", () => {
  assertThrows(
    () => toOpencodeMarkdown(parseSubagent(subagentMarkdown({ frontmatter: "name: q" }))),
    Error,
    "frontmatter に description がありません",
  );
});
