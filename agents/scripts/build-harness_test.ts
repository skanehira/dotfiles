import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import {
  MANIFEST_NAME,
  assertSafeOutRoot,
  buildFile,
  buildTree,
  mergeSections,
  planPrune,
  removeDotfilesLinks,
  substitute,
  type Vocabulary,
} from "./build-harness.ts";
import { GENERATED_MARKER } from "./subagent-format.ts";

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

// ------------------------------------------------------- planPrune / buildTree

Deno.test("planPrune_returns_paths_in_the_previous_manifest_that_the_new_build_no_longer_writes", () => {
  assertEquals(
    planPrune(["a.md", "b/c.md", "d.sh"], ["a.md", "d.sh"]),
    ["b/c.md"],
  );
});

Deno.test("planPrune_with_nothing_dropped_returns_an_empty_list", () => {
  assertEquals(planPrune(["a.md"], ["a.md", "new.md"]), []);
});

/** base / overlay / out の 3 つを用意して後片付けまで面倒を見る */
async function withTrees(
  fn: (t: { base: string; overlay: string; out: string; dotfiles: string }) => Promise<void>,
) {
  const dotfiles = await Deno.makeTempDir();
  const base = `${dotfiles}/agents`;
  const overlay = `${dotfiles}/overlay`;
  const out = await Deno.makeTempDir();
  await Deno.mkdir(base, { recursive: true });
  await Deno.mkdir(overlay, { recursive: true });
  try {
    await fn({ base, overlay, out, dotfiles });
  } finally {
    await Deno.remove(dotfiles, { recursive: true });
    await Deno.remove(out, { recursive: true });
  }
}

const VOCAB_FIXTURE: Vocabulary = {
  "ask-user": { claude: "AskUserQuestion", codex: "request_user_input", opencode: "question" },
};

Deno.test("buildTree_merges_the_overlay_section_then_substitutes_for_the_runtime", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    await Deno.writeTextFile(
      `${base}/g.md`,
      "# t\n\n## 確認\n\nbase は {{@ask-user}} を使う。\n\n## 残り\n\nそのまま。\n",
    );
    await Deno.writeTextFile(
      `${overlay}/g.md`,
      "## 確認\n\noverlay は {{@ask-user}} を使う。\n",
    );
    await buildTree({
      baseDir: base,
      overlayDir: overlay,
      outDir: out,
      runtime: "codex",
      vocabulary: VOCAB_FIXTURE,
      dotfilesRoot: dotfiles,
    });
    assertEquals(
      await Deno.readTextFile(`${out}/g.md`),
      "# t\n\n## 確認\n\noverlay は request_user_input を使う。\n\n## 残り\n\nそのまま。\n",
    );
  });
});

Deno.test("buildTree_copies_non_markdown_files_preserving_the_executable_bit", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    await Deno.mkdir(`${base}/s/scripts`, { recursive: true });
    await Deno.writeTextFile(`${base}/s/scripts/run.sh`, "#!/bin/sh\necho {{@ask-user}}\n");
    await Deno.chmod(`${base}/s/scripts/run.sh`, 0o755);
    await Deno.writeTextFile(`${base}/s/data.json`, '{"k":"{{@ask-user}}"}\n');
    await buildTree({
      baseDir: base,
      overlayDir: overlay,
      outDir: out,
      runtime: "codex",
      vocabulary: VOCAB_FIXTURE,
      dotfilesRoot: dotfiles,
    });
    // .md 以外は置換もマージもせず素通し。実行ビットは保つ
    assertEquals(await Deno.readTextFile(`${out}/s/scripts/run.sh`), "#!/bin/sh\necho {{@ask-user}}\n");
    assertEquals((Deno.statSync(`${out}/s/scripts/run.sh`).mode! & 0o777), 0o755);
    assertEquals((Deno.statSync(`${out}/s/data.json`).mode! & 0o777), 0o644);
  });
});

Deno.test("buildTree_excludes_ds_store_from_the_output", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    await Deno.writeTextFile(`${base}/a.md`, "# a\n");
    await Deno.writeTextFile(`${base}/.DS_Store`, "junk");
    await buildTree({
      baseDir: base, overlayDir: overlay, outDir: out,
      runtime: "codex", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
    });
    assertEquals([...Deno.readDirSync(out)].map((e) => e.name).sort(), [".harness-manifest.json", "a.md"]);
  });
});

Deno.test("buildTree_prunes_only_what_its_own_previous_manifest_listed_and_keeps_foreign_files", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    await Deno.writeTextFile(`${base}/keep.md`, "# keep\n");
    await Deno.writeTextFile(`${base}/gone.md`, "# gone\n");
    await buildTree({
      baseDir: base, overlayDir: overlay, outDir: out,
      runtime: "codex", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
    });
    // 他ツールが置いたファイル。manifest に無いので残すべき
    await Deno.writeTextFile(`${out}/foreign.md`, "# foreign\n");
    await Deno.remove(`${base}/gone.md`);

    const result = await buildTree({
      baseDir: base, overlayDir: overlay, outDir: out,
      runtime: "codex", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
    });
    assertEquals(result.pruned, ["gone.md"]);
    assertEquals(
      [...Deno.readDirSync(out)].map((e) => e.name).sort(),
      [".harness-manifest.json", "foreign.md", "keep.md"],
    );
  });
});

Deno.test("buildTree_removes_a_legacy_symlink_into_dotfiles_instead_of_writing_the_output_through_it", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    // 旧方式は正本のスキル 1 本ずつを配布先へ symlink していた。残っていると
    // mkdir -p + rename がリンク越しに解決して正本を生成物で上書きする
    await Deno.mkdir(`${base}/alpha`, { recursive: true });
    const canonical = `${base}/alpha/SKILL.md`;
    await Deno.writeTextFile(canonical, "# alpha\n\n{{@ask-user}} を使う。\n");
    await Deno.symlink(`${base}/alpha`, `${out}/alpha`);
    // 他ツールが張った dotfiles 外の symlink は撤去の対象外
    const foreign = await Deno.makeTempDir();
    await Deno.symlink(foreign, `${out}/foreign`);

    try {
      await buildTree({
        baseDir: base, overlayDir: overlay, outDir: out,
        runtime: "codex", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
      });

      assertEquals(await Deno.readTextFile(canonical), "# alpha\n\n{{@ask-user}} を使う。\n");
      assertEquals(Deno.lstatSync(`${out}/alpha`).isSymlink, false);
      assertEquals(
        await Deno.readTextFile(`${out}/alpha/SKILL.md`),
        "# alpha\n\nrequest_user_input を使う。\n",
      );
      assertEquals(Deno.readLinkSync(`${out}/foreign`), foreign);
    } finally {
      await Deno.remove(foreign, { recursive: true });
    }
  });
});

Deno.test("buildTree_that_fails_before_writing_leaves_a_legacy_symlink_in_place", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    // 撤去してから生成が落ちると、旧リンクも生成物も無い空の配布先が残る。
    // 撤去は書き込み直前に行い、失敗時は元の状態のままにする
    await Deno.mkdir(`${base}/alpha`, { recursive: true });
    await Deno.writeTextFile(`${base}/alpha/SKILL.md`, "# alpha\n\n{{@not-in-vocabulary}}\n");
    await Deno.symlink(`${base}/alpha`, `${out}/alpha`);

    await assertRejects(
      () =>
        buildTree({
          baseDir: base, overlayDir: overlay, outDir: out,
          runtime: "codex", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
        }),
      Error,
      "語彙表に {{@not-in-vocabulary}} がありません",
    );
    assertEquals(Deno.lstatSync(`${out}/alpha`).isSymlink, true);
    assertEquals(Deno.readLinkSync(`${out}/alpha`), `${base}/alpha`);
  });
});

Deno.test("buildTree_with_an_out_dir_inside_dotfiles_root_throws_before_writing_anything", async () => {
  await withTrees(async ({ base, overlay, dotfiles }) => {
    await Deno.writeTextFile(`${base}/a.md`, "# a\n");
    const unsafe = `${dotfiles}/agents/skills`;
    await assertRejects(
      () =>
        buildTree({
          baseDir: base, overlayDir: overlay, outDir: unsafe,
          runtime: "codex", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
        }),
      Error,
      "出力先が正本の中を指しています",
    );
  });
});

Deno.test("buildTree_with_an_undefined_placeholder_throws_and_leaves_the_out_dir_untouched", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    await Deno.writeTextFile(`${base}/a.md`, "# a\n\n{{@not-in-vocabulary}}\n");
    await assertRejects(
      () =>
        buildTree({
          baseDir: base, overlayDir: overlay, outDir: out,
          runtime: "codex", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
        }),
      Error,
      "語彙表に {{@not-in-vocabulary}} がありません",
    );
    // staging に書いてから rename するので、失敗時に出力先は空のまま
    assertEquals([...Deno.readDirSync(out)].length, 0);
  });
});

// ------------------------------------------------- removeDotfilesLinks

Deno.test("removeDotfilesLinks_removes_only_symlinks_resolving_into_dotfiles_and_keeps_real_dirs", async () => {
  const dotfiles = await Deno.makeTempDir();
  const shared = await Deno.makeTempDir();
  const elsewhere = await Deno.makeTempDir();
  try {
    await Deno.mkdir(`${dotfiles}/agents/skills/mine`, { recursive: true });
    // 我々が張った symlink (撤去対象)
    await Deno.symlink(`${dotfiles}/agents/skills/mine`, `${shared}/mine`);
    // 他ツールが置いた実体 (残す)
    await Deno.mkdir(`${shared}/foreign-real`);
    // 他所を指す symlink (残す)
    await Deno.symlink(elsewhere, `${shared}/foreign-link`);

    assertEquals(await removeDotfilesLinks(shared, dotfiles), ["mine"]);
    assertEquals(
      [...Deno.readDirSync(shared)].map((e) => e.name).sort(),
      ["foreign-link", "foreign-real"],
    );
  } finally {
    for (const d of [dotfiles, shared, elsewhere]) await Deno.remove(d, { recursive: true });
  }
});

Deno.test("removeDotfilesLinks_removes_a_broken_link_into_dotfiles_and_keeps_a_broken_link_outside", async () => {
  const dotfiles = await Deno.makeTempDir();
  const outside = await Deno.makeTempDir();
  const shared = await Deno.makeTempDir();
  try {
    // 壊れたリンクは realPath で解決できないので readlink 側にフォールバックする。
    // その戻り値を canonicalize しないと、/var → /private/var のような symlink を挟む
    // 一時ディレクトリで dotfilesRoot 側とだけ形が揃い、判定が滑る
    await Deno.symlink(`${dotfiles}/gone`, `${shared}/mine`);
    await Deno.symlink(`${outside}/gone`, `${shared}/theirs`);

    assertEquals(await removeDotfilesLinks(shared, dotfiles), ["mine"]);
    assertEquals(Deno.lstatSync(`${shared}/theirs`).isSymlink, true);
  } finally {
    for (const dir of [dotfiles, outside, shared]) {
      await Deno.remove(dir, { recursive: true });
    }
  }
});

Deno.test("removeDotfilesLinks_on_a_missing_directory_returns_an_empty_list", async () => {
  const dotfiles = await Deno.makeTempDir();
  try {
    assertEquals(await removeDotfilesLinks(`${dotfiles}/never-created`, dotfiles), []);
  } finally {
    await Deno.remove(dotfiles, { recursive: true });
  }
});

// ------------------------------------------------------------------ buildFile

Deno.test("buildFile_merges_the_overlay_then_substitutes_and_writes_to_the_destination", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    await Deno.writeTextFile(`${base}/AGENTS.md`, "# g\n\n## 確認\n\n{{@ask-user}} で聞く。\n");
    await Deno.writeTextFile(`${overlay}/AGENTS.md`, "## 確認\n\n{{@ask-user}} を使う。\n");
    await buildFile({
      baseFile: `${base}/AGENTS.md`,
      overlayFile: `${overlay}/AGENTS.md`,
      outFile: `${out}/CLAUDE.md`,
      runtime: "codex",
      vocabulary: VOCAB_FIXTURE,
      dotfilesRoot: dotfiles,
    });
    assertEquals(
      await Deno.readTextFile(`${out}/CLAUDE.md`),
      "# g\n\n## 確認\n\nrequest_user_input を使う。\n",
    );
  });
});

Deno.test("buildFile_without_an_overlay_writes_the_substituted_base", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    await Deno.writeTextFile(`${base}/AGENTS.md`, "# g\n\n{{@ask-user}} で聞く。\n");
    await buildFile({
      baseFile: `${base}/AGENTS.md`,
      overlayFile: `${overlay}/AGENTS.md`,
      outFile: `${out}/CLAUDE.md`,
      runtime: "claude",
      vocabulary: VOCAB_FIXTURE,
      dotfilesRoot: dotfiles,
    });
    assertEquals(await Deno.readTextFile(`${out}/CLAUDE.md`), "# g\n\nAskUserQuestion で聞く。\n");
  });
});

Deno.test("buildFile_with_a_destination_inside_dotfiles_root_throws", async () => {
  await withTrees(async ({ base, overlay, dotfiles }) => {
    await Deno.writeTextFile(`${base}/AGENTS.md`, "# g\n");
    await assertRejects(
      () =>
        buildFile({
          baseFile: `${base}/AGENTS.md`,
          overlayFile: `${overlay}/AGENTS.md`,
          outFile: `${dotfiles}/agents/CLAUDE.md`,
          runtime: "claude",
          vocabulary: VOCAB_FIXTURE,
          dotfilesRoot: dotfiles,
        }),
      Error,
      "出力先が正本の中を指しています",
    );
  });
});

// --------------------------------------------------- subagent の書式変換

const SUBAGENT_MD = `---
name: reviewer
description: 差分を {{@ask-user}} 抜きで検査する
tools: Read, Grep
model: opus
---

# reviewer

確認が要るときは {{@ask-user}} を使う。
`;

Deno.test("buildTree_with_the_codex_subagent_format_substitutes_then_emits_toml_named_by_the_frontmatter", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    await Deno.writeTextFile(`${base}/any-filename.md`, SUBAGENT_MD);
    const result = await buildTree({
      baseDir: base, overlayDir: overlay, outDir: out,
      runtime: "codex", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
      subagentFormat: "codex",
    });
    assertEquals(result.written, ["reviewer.toml"]);
    assertEquals(
      await Deno.readTextFile(`${out}/reviewer.toml`),
      `${GENERATED_MARKER}
name = "reviewer"
description = "差分を request_user_input 抜きで検査する"
developer_instructions = '''
# reviewer

確認が要るときは request_user_input を使う。
'''
`,
    );
  });
});

Deno.test("buildTree_with_the_opencode_subagent_format_emits_markdown_with_the_subagent_mode", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    await Deno.writeTextFile(`${base}/any-filename.md`, SUBAGENT_MD);
    const result = await buildTree({
      baseDir: base, overlayDir: overlay, outDir: out,
      runtime: "opencode", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
      subagentFormat: "opencode",
    });
    assertEquals(result.written, ["reviewer.md"]);
    assertEquals(
      await Deno.readTextFile(`${out}/reviewer.md`),
      `---
${GENERATED_MARKER}
description: 差分を question 抜きで検査する
mode: subagent
---

# reviewer

確認が要るときは question を使う。
`,
    );
  });
});

Deno.test("mergeSections_with_text_before_the_first_overlay_heading_throws_instead_of_dropping_it", () => {
  // overlay の前文はマージキーを持たないので黙って落ちる。F3 で overlay を書くときに
  // 気づけないため例外にする。
  assertThrows(
    () => mergeSections("# t\n\n## あ\n\nbase。\n", "# 別の見出し\n\n落ちる前文。\n\n## あ\n\noverlay。\n"),
    Error,
    "overlay の最初の見出しより前に本文があります",
  );
});

Deno.test("mergeSections_allows_blank_lines_before_the_first_overlay_heading", () => {
  assertEquals(
    mergeSections("# t\n\n## あ\n\nbase。\n", "\n\n## あ\n\noverlay。\n"),
    "# t\n\n## あ\n\noverlay。\n",
  );
});

// ------------------------------------------- metadata.runtimes による配布先の限定

/** SKILL.md の最小形。`metadata.runtimes` は省略できる */
function skillMarkdown(name: string, runtimes?: string): string {
  const metadata = runtimes === undefined ? "" : `metadata:\n  runtimes: ${runtimes}\n`;
  return `---\nname: ${name}\ndescription: ${name} の説明。\n${metadata}---\n\n# ${name}\n\n確認は {{@ask-user}} で行う。\n`;
}

/** 配布先の台帳に載っているパス一覧 */
function manifestPaths(outDir: string): string[] {
  return JSON.parse(Deno.readTextFileSync(`${outDir}/${MANIFEST_NAME}`)).paths;
}

Deno.test("buildTree_omits_the_whole_directory_of_a_skill_whose_runtimes_excludes_the_runtime", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    await Deno.mkdir(`${base}/claude-only/references`, { recursive: true });
    await Deno.writeTextFile(`${base}/claude-only/SKILL.md`, skillMarkdown("claude-only", "claude"));
    // SKILL.md 以外も出さない (references / scripts ごと落とす)
    await Deno.writeTextFile(`${base}/claude-only/references/log.md`, "# log\n");
    await Deno.mkdir(`${base}/everywhere`, { recursive: true });
    await Deno.writeTextFile(`${base}/everywhere/SKILL.md`, skillMarkdown("everywhere"));

    const result = await buildTree({
      baseDir: base, overlayDir: overlay, outDir: out,
      runtime: "codex", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
    });

    assertEquals(result.written, ["everywhere/SKILL.md"]);
    assertEquals(manifestPaths(out), ["everywhere/SKILL.md"]);
    assertEquals(
      [...Deno.readDirSync(out)].map((e) => e.name).sort(),
      [".harness-manifest.json", "everywhere"],
    );
  });
});

Deno.test("buildTree_distributes_a_skill_whose_runtimes_lists_the_runtime_among_several", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    await Deno.mkdir(`${base}/two-runtimes`, { recursive: true });
    await Deno.writeTextFile(
      `${base}/two-runtimes/SKILL.md`,
      skillMarkdown("two-runtimes", "claude, codex"),
    );

    const result = await buildTree({
      baseDir: base, overlayDir: overlay, outDir: out,
      runtime: "codex", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
    });

    assertEquals(result.written, ["two-runtimes/SKILL.md"]);
    assertEquals(
      await Deno.readTextFile(`${out}/two-runtimes/SKILL.md`),
      "---\nname: two-runtimes\ndescription: two-runtimes の説明。\nmetadata:\n  runtimes: claude, codex\n---\n\n# two-runtimes\n\n確認は request_user_input で行う。\n",
    );
  });
});

Deno.test("buildTree_with_a_runtime_name_absent_from_the_vocabulary_throws_naming_it_and_writes_nothing", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    await Deno.mkdir(`${base}/typo`, { recursive: true });
    // typo を黙って通すと全ランタイムから外れ、次の生成で prune が配布済みのものを消す
    await Deno.writeTextFile(`${base}/typo/SKILL.md`, skillMarkdown("typo", "claud"));

    await assertRejects(
      () =>
        buildTree({
          baseDir: base, overlayDir: overlay, outDir: out,
          runtime: "codex", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
        }),
      Error,
      "typo/SKILL.md の runtimes に不明なランタイム 'claud' があります",
    );
    assertEquals([...Deno.readDirSync(out)].map((e) => e.name), []);
  });
});

Deno.test("buildTree_prunes_a_distributed_skill_that_later_gains_a_runtimes_excluding_the_runtime", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    await Deno.mkdir(`${base}/later-limited`, { recursive: true });
    await Deno.writeTextFile(`${base}/later-limited/SKILL.md`, skillMarkdown("later-limited"));
    await buildTree({
      baseDir: base, overlayDir: overlay, outDir: out,
      runtime: "codex", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
    });

    // 配布済みのスキルを後から Claude 専用にする
    await Deno.writeTextFile(
      `${base}/later-limited/SKILL.md`,
      skillMarkdown("later-limited", "claude"),
    );
    const result = await buildTree({
      baseDir: base, overlayDir: overlay, outDir: out,
      runtime: "codex", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
    });

    assertEquals(result.pruned, ["later-limited/SKILL.md"]);
    assertEquals(manifestPaths(out), []);
  });
});

Deno.test("buildTree_without_a_vocabulary_refuses_to_read_metadata_runtimes_instead_of_skipping_the_check", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    // 語彙表が空だと既知のランタイム名を引けない。検証を飛ばすと typo が無音で通り、
    // 全ランタイムから外れたスキルを次の生成で prune が消す
    await Deno.mkdir(`${base}/plain`, { recursive: true });
    await Deno.writeTextFile(
      `${base}/plain/SKILL.md`,
      "---\nname: plain\nmetadata:\n  runtimes: codex\n---\n\n# plain\n",
    );

    await assertRejects(
      () =>
        buildTree({
          baseDir: base, overlayDir: overlay, outDir: out,
          runtime: "codex", vocabulary: {}, dotfilesRoot: dotfiles,
        }),
      Error,
      "plain/SKILL.md の runtimes を検証できません",
    );
  });
});

/**
 * `metadata.runtimes` として実際に書かれうる入力を、配布 / 除外 / 例外のどれになるか全件 pin する。
 *
 * ここを空けておくと、行末スペース 1 バイトの違い (`runtimes:` と `runtimes: `) が
 * 「全配布」と「全除外」という正反対の結果になり、後者では prune が配布済みのスキルを
 * 黙って消す。曖昧な書き方はすべて例外に倒す (fail-closed)。
 */
const RUNTIMES_INPUTS: Array<
  { label: string; frontmatter: string; outcome: "配布" | "除外" } | {
    label: string;
    frontmatter: string;
    outcome: "例外";
    /** 書き手が SKILL.md をどう直すかの唯一の手掛かりなので、診断も入力ごとに固定する */
    message: string;
  }
> = [
  { label: "宣言なし", frontmatter: "name: s\n", outcome: "配布" },
  { label: "自ランタイムのみ", frontmatter: "name: s\nmetadata:\n  runtimes: codex\n", outcome: "配布" },
  { label: "自ランタイムを含む複数", frontmatter: "name: s\nmetadata:\n  runtimes: claude, codex\n", outcome: "配布" },
  { label: "タブ字下げ", frontmatter: "name: s\nmetadata:\n\truntimes: codex\n", outcome: "配布" },
  { label: "末尾カンマ", frontmatter: "name: s\nmetadata:\n  runtimes: codex,\n", outcome: "配布" },
  { label: "metadata に他キー混在", frontmatter: "name: s\nmetadata:\n  license: MIT\n  runtimes: codex\n", outcome: "配布" },
  // 実在の書式 (dev-spec / fullstack-app-builder の description は >- の折り返し)。
  // 値の中の 1 行が runtimes: で始まっても、限定の宣言ではないので触ってはいけない
  {
    label: "ブロックスカラーの折り返し",
    frontmatter: "name: s\ndescription: >-\n  設計ループ。\n  runtimes: claude と書くと Claude だけに配られる。\n",
    outcome: "配布",
  },
  { label: "大文字 Runtimes", frontmatter: "name: s\nmetadata:\n  Runtimes: claude\n", outcome: "配布" },
  { label: "frontmatter 未終端", frontmatter: null as unknown as string, outcome: "配布" },
  { label: "他ランタイムのみ", frontmatter: "name: s\nmetadata:\n  runtimes: claude\n", outcome: "除外" },
  { label: "宣言が 2 行 (最初が勝つ)", frontmatter: "name: s\nmetadata:\n  runtimes: claude\n  runtimes: codex\n", outcome: "除外" },
  { label: "metadata の二段入れ子", frontmatter: "name: s\nmetadata:\n  catalog:\n    runtimes: claude\n", outcome: "除外" },
  {
    label: "値なし",
    frontmatter: "name: s\nmetadata:\n  runtimes:\n",
    outcome: "例外",
    message: "s/SKILL.md の runtimes に値がありません",
  },
  {
    label: "行末スペースのみ",
    frontmatter: "name: s\nmetadata:\n  runtimes: \n",
    outcome: "例外",
    message: "s/SKILL.md の runtimes に値がありません",
  },
  {
    label: "カンマのみ",
    frontmatter: "name: s\nmetadata:\n  runtimes: ,\n",
    outcome: "例外",
    message: "s/SKILL.md の runtimes に値がありません",
  },
  {
    label: "リスト形式",
    frontmatter: "name: s\nmetadata:\n  runtimes:\n    - codex\n",
    outcome: "例外",
    message: "s/SKILL.md の runtimes に値がありません",
  },
  {
    label: "トップレベル",
    frontmatter: "name: s\nruntimes: codex\n",
    outcome: "例外",
    message: "s/SKILL.md の runtimes は frontmatter の metadata: の直下に置く",
  },
  {
    label: "metadata がマップでない",
    frontmatter: "name: s\nmetadata: {license: MIT}\n  runtimes: codex\n",
    outcome: "例外",
    message: "s/SKILL.md の runtimes は frontmatter の metadata: の直下に置く",
  },
  {
    label: "metadata 以外の配下",
    frontmatter: "name: s\nother:\n  runtimes: codex\n",
    outcome: "例外",
    message: "s/SKILL.md の runtimes は frontmatter の metadata: の直下に置く",
  },
  {
    label: "metadata ブロックの後の別キー配下",
    frontmatter: "name: s\nmetadata:\n  license: MIT\nother:\n  runtimes: codex\n",
    outcome: "例外",
    message: "s/SKILL.md の runtimes は frontmatter の metadata: の直下に置く",
  },
  {
    label: "インラインマップ",
    frontmatter: "name: s\nmetadata: {runtimes: codex}\n",
    outcome: "例外",
    message: "s/SKILL.md の metadata: はブロック形式で書く",
  },
  {
    label: "フロー形式",
    frontmatter: "name: s\nmetadata:\n  runtimes: [claude, codex]\n",
    outcome: "例外",
    message: "s/SKILL.md の runtimes に不明なランタイム '[claude' があります",
  },
  {
    label: "引用符つき",
    frontmatter: 'name: s\nmetadata:\n  runtimes: "codex"\n',
    outcome: "例外",
    message: `s/SKILL.md の runtimes に不明なランタイム '"codex"' があります`,
  },
  {
    label: "行末コメント",
    frontmatter: "name: s\nmetadata:\n  runtimes: codex # codex だけ\n",
    outcome: "例外",
    message: "s/SKILL.md の runtimes に不明なランタイム 'codex # codex だけ' があります",
  },
];

Deno.test("buildTree_pins_every_way_metadata_runtimes_can_be_written_to_distribute_or_exclude_or_throw", async () => {
  for (const input of RUNTIMES_INPUTS) {
    await withTrees(async ({ base, overlay, out, dotfiles }) => {
      await Deno.mkdir(`${base}/s`, { recursive: true });
      // frontmatter が null の行は「終端の --- が無い SKILL.md」を表す
      const markdown = input.frontmatter === null
        ? "---\nname: s\nmetadata:\n  runtimes: claude\n\n# s\n"
        : `---\n${input.frontmatter}---\n\n# s\n`;
      await Deno.writeTextFile(`${base}/s/SKILL.md`, markdown);
      const build = () =>
        buildTree({
          baseDir: base, overlayDir: overlay, outDir: out,
          runtime: "codex", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
        });

      if (input.outcome === "例外") {
        await assertRejects(build, Error, input.message, `${input.label} の診断が違う`);
        assertEquals([...Deno.readDirSync(out)].map((e) => e.name), [], `${input.label} は何も書かないべき`);
        return;
      }
      const result = await build();
      assertEquals(
        result.written,
        input.outcome === "配布" ? ["s/SKILL.md"] : [],
        `${input.label} は ${input.outcome} されるべき`,
      );
    });
  }
});

Deno.test("buildTree_reads_metadata_runtimes_from_a_file_with_crlf_line_endings", async () => {
  await withTrees(async ({ base, overlay, out, dotfiles }) => {
    await Deno.mkdir(`${base}/crlf`, { recursive: true });
    await Deno.writeTextFile(
      `${base}/crlf/SKILL.md`,
      "---\r\nname: crlf\r\nmetadata:\r\n  runtimes: claude\r\n---\r\n\r\n# crlf\r\n",
    );
    const result = await buildTree({
      baseDir: base, overlayDir: overlay, outDir: out,
      runtime: "codex", vocabulary: VOCAB_FIXTURE, dotfilesRoot: dotfiles,
    });
    assertEquals(result.written, []);
  });
});
