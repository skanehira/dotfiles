import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  assertSafeOutRoot,
  mergeSections,
  substitute,
  type Vocabulary,
} from "./build-harness.ts";

/**
 * 実際の vocabulary.json に近い最小の語彙表。
 * task 系を 3 つに分けているのは、Claude 方向を全単射に保って F2 の byte 一致検証を
 * 成立させるため (1 つに畳むと TaskCreate / TaskUpdate / TodoWrite に戻せない)。
 */
const VOCABULARY: Vocabulary = {
  "ask-user": {
    claude: "AskUserQuestion",
    codex: "request_user_input",
    opencode: "question",
  },
  "task-create": { claude: "TaskCreate", codex: "update_plan", opencode: "todowrite" },
  "task-update": { claude: "TaskUpdate", codex: "update_plan", opencode: "todowrite" },
  "todo-write": { claude: "TodoWrite", codex: "update_plan", opencode: "todowrite" },
  "rules-root": {
    claude: "~/.claude/rules",
    codex: "~/.agents/rules/codex",
    opencode: "~/.agents/rules/opencode",
  },
};

// ---------------------------------------------------------------- substitute

Deno.test("substitute_with_claude_runtime_expands_every_placeholder_to_the_claude_value", () => {
  assertEquals(
    substitute(
      "確認は {{@ask-user}} で行い、進捗は {{@todo-write}} に書く。詳細 → {{@rules-root}}/core/tdd.md",
      VOCABULARY,
      "claude",
    ),
    "確認は AskUserQuestion で行い、進捗は TodoWrite に書く。詳細 → ~/.claude/rules/core/tdd.md",
  );
});

Deno.test("substitute_with_codex_runtime_collapses_the_three_task_placeholders_to_update_plan", () => {
  assertEquals(
    substitute(
      "{{@task-create}} / {{@task-update}} / {{@todo-write}}",
      VOCABULARY,
      "codex",
    ),
    "update_plan / update_plan / update_plan",
  );
});

Deno.test("substitute_leaves_bare_tool_names_and_braces_without_the_at_sign_untouched", () => {
  const text = "AskUserQuestion を rg で探す。<transcript>{{transcript}}</transcript> と {{.Repository}} と {{ANNUAL_REPORT}}";
  assertEquals(substitute(text, VOCABULARY, "codex"), text);
});

Deno.test("substitute_expands_placeholders_inside_code_fences", () => {
  assertEquals(
    substitute(
      "```ts\n{{@ask-user}}({ questions: [] })\n```\n",
      VOCABULARY,
      "opencode",
    ),
    "```ts\nquestion({ questions: [] })\n```\n",
  );
});

Deno.test("substitute_with_a_placeholder_missing_from_the_vocabulary_throws_naming_it", () => {
  assertThrows(
    () => substitute("次は {{@web-fetch}} で取る", VOCABULARY, "claude"),
    Error,
    "語彙表に {{@web-fetch}} がありません",
  );
});

Deno.test("substitute_with_a_runtime_missing_from_an_entry_throws_naming_both", () => {
  const partial: Vocabulary = { "ask-user": { claude: "AskUserQuestion" } };
  assertThrows(
    () => substitute("{{@ask-user}}", partial, "codex"),
    Error,
    "{{@ask-user}} に codex の値がありません",
  );
});

// ------------------------------------------------------------ mergeSections

Deno.test("mergeSections_replaces_the_section_whose_heading_matches_and_keeps_the_others", () => {
  const base = `# 手順

前文。

## 準備

base の準備。

## 実行

base の実行。

## 後始末

base の後始末。
`;
  const overlay = `## 実行

overlay の実行。
`;
  assertEquals(
    mergeSections(base, overlay),
    `# 手順

前文。

## 準備

base の準備。

## 実行

overlay の実行。

## 後始末

base の後始末。
`,
  );
});

Deno.test("mergeSections_replacing_an_h2_swallows_its_h3_descendants", () => {
  const base = `# t

## 失敗と対策

### 1 つ目

base の 1 つ目。

### 2 つ目

base の 2 つ目。

## 適用範囲

base の適用範囲。
`;
  const overlay = `## 失敗と対策

Codex では該当しない。
`;
  assertEquals(
    mergeSections(base, overlay),
    `# t

## 失敗と対策

Codex では該当しない。

## 適用範囲

base の適用範囲。
`,
  );
});

Deno.test("mergeSections_replacing_an_h3_leaves_its_sibling_and_parent_intact", () => {
  const base = `# t

## ワークフロー

### フェーズ1

base の 1。

### フェーズ2

base の 2。
`;
  const overlay = `### フェーズ2

overlay の 2。
`;
  assertEquals(
    mergeSections(base, overlay),
    `# t

## ワークフロー

### フェーズ1

base の 1。

### フェーズ2

overlay の 2。
`,
  );
});

Deno.test("mergeSections_appends_headings_absent_from_base_at_the_end", () => {
  const base = `# t

## あ

base のあ。
`;
  const overlay = `## い

overlay のい。
`;
  assertEquals(
    mergeSections(base, overlay),
    `# t

## あ

base のあ。

## い

overlay のい。
`,
  );
});

Deno.test("mergeSections_does_not_treat_hash_lines_inside_code_fences_as_headings", () => {
  const base = `# t

## テンプレート

\`\`\`markdown
## 概要

ここに書く。
\`\`\`

## 備考

base の備考。
`;
  const overlay = `## 概要

overlay の概要。
`;
  // フェンス内の `## 概要` は見出しではないので base に一致するものが無く、末尾へ追加される
  assertEquals(
    mergeSections(base, overlay),
    `# t

## テンプレート

\`\`\`markdown
## 概要

ここに書く。
\`\`\`

## 備考

base の備考。

## 概要

overlay の概要。
`,
  );
});

Deno.test("mergeSections_tracks_tilde_fences_as_well_as_backtick_fences", () => {
  const base = `# t

## テンプレート

~~~markdown
## 概要
~~~

## 備考

base の備考。
`;
  const overlay = `## 備考

overlay の備考。
`;
  assertEquals(
    mergeSections(base, overlay),
    `# t

## テンプレート

~~~markdown
## 概要
~~~

## 備考

overlay の備考。
`,
  );
});

Deno.test("mergeSections_does_not_treat_hash_lines_inside_frontmatter_as_headings", () => {
  const base = `---
name: t
description: "## 罠"
---

## 本体

base の本体。
`;
  const overlay = `## 本体

overlay の本体。
`;
  assertEquals(
    mergeSections(base, overlay),
    `---
name: t
description: "## 罠"
---

## 本体

overlay の本体。
`,
  );
});

Deno.test("mergeSections_with_an_overlay_that_has_no_headings_replaces_the_whole_document", () => {
  const base = `# 調査

- 網羅的に調べる
- 途中で止めない
`;
  const overlay = `# 調査

Codex 版の全文。
`;
  assertEquals(mergeSections(base, overlay), overlay);
});

Deno.test("mergeSections_with_an_empty_overlay_returns_the_base_unchanged", () => {
  const base = `# t

## あ

base のあ。
`;
  assertEquals(mergeSections(base, ""), base);
});

Deno.test("mergeSections_with_a_heading_repeated_in_base_throws_naming_the_heading", () => {
  const base = `# t

## あ

1 つ目。

## あ

2 つ目。
`;
  assertThrows(
    () => mergeSections(base, "## あ\n\nx\n"),
    Error,
    "base に見出し '## あ' が 2 回現れます",
  );
});

// -------------------------------------------------------- assertSafeOutRoot

Deno.test("assertSafeOutRoot_with_a_plain_directory_outside_dotfiles_passes", async () => {
  const dotfiles = await Deno.makeTempDir();
  const out = await Deno.makeTempDir();
  try {
    assertSafeOutRoot(out, dotfiles);
  } finally {
    await Deno.remove(dotfiles, { recursive: true });
    await Deno.remove(out, { recursive: true });
  }
});

Deno.test("assertSafeOutRoot_with_a_symlink_out_root_throws_instead_of_writing_through_it", async () => {
  const dotfiles = await Deno.makeTempDir();
  const parent = await Deno.makeTempDir();
  try {
    const link = `${parent}/skills`;
    await Deno.symlink(dotfiles, link);
    assertThrows(
      () => assertSafeOutRoot(link, dotfiles),
      Error,
      `出力先が symlink です: ${link}`,
    );
  } finally {
    await Deno.remove(dotfiles, { recursive: true });
    await Deno.remove(parent, { recursive: true });
  }
});

Deno.test("assertSafeOutRoot_with_a_path_resolving_inside_dotfiles_root_throws", async () => {
  const dotfiles = await Deno.makeTempDir();
  try {
    const inside = `${dotfiles}/agents/skills`;
    await Deno.mkdir(inside, { recursive: true });
    assertThrows(
      () => assertSafeOutRoot(inside, dotfiles),
      Error,
      "出力先が正本の中を指しています",
    );
  } finally {
    await Deno.remove(dotfiles, { recursive: true });
  }
});

Deno.test("assertSafeOutRoot_resolves_an_intermediate_symlink_hop_before_comparing", async () => {
  // ~/.claude/skills は /nix/store の link farm を 1 段挟んで dotfiles に着く。
  // 素のパス比較だと素通りしてしまうので realpath で解決してから比較する。
  const dotfiles = await Deno.makeTempDir();
  const farm = await Deno.makeTempDir();
  try {
    const inside = `${dotfiles}/agents/skills`;
    await Deno.mkdir(inside, { recursive: true });
    const hop = `${farm}/skills`;
    await Deno.symlink(inside, hop);
    const viaHop = `${farm}/skills/nested`;
    await Deno.mkdir(viaHop, { recursive: true });
    assertThrows(
      () => assertSafeOutRoot(viaHop, dotfiles),
      Error,
      "出力先が正本の中を指しています",
    );
  } finally {
    await Deno.remove(dotfiles, { recursive: true });
    await Deno.remove(farm, { recursive: true });
  }
});

Deno.test("assertSafeOutRoot_with_a_not_yet_created_directory_checks_its_parent", async () => {
  const dotfiles = await Deno.makeTempDir();
  try {
    assertThrows(
      () => assertSafeOutRoot(`${dotfiles}/agents/does-not-exist-yet`, dotfiles),
      Error,
      "出力先が正本の中を指しています",
    );
  } finally {
    await Deno.remove(dotfiles, { recursive: true });
  }
});
