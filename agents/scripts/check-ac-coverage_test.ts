import { assertEquals } from "jsr:@std/assert@1";
import { checkAcCoverage } from "./check-ac-coverage.ts";

/** USER_STORIES.md のフィクスチャ。realizes が null なら「実現するユースケース」行を書かない */
function stories(
  entries: { id: string; realizes: string | null }[],
  wontTable = "",
): string {
  const sections = entries.map(({ id, realizes }) =>
    [
      `#### ${id}: ストーリー ${id}`,
      "",
      "- **開発者として**",
      "- **何かをしたい**",
      "- **なぜなら** 価値があるから",
      "",
      ...(realizes === null ? [] : [`**実現するユースケース**: ${realizes}`, ""]),
      "**エピック**: E1",
      "",
    ].join("\n")
  );
  return [
    "# ユーザーストーリー",
    "",
    "## ストーリー一覧",
    "",
    "### Must（必須）",
    "",
    ...sections,
    "### Won't（今回はやらない）",
    "",
    wontTable,
  ].join("\n");
}

/** UC 見出しと受け入れ基準の行だけを持つ USECASES.md のフィクスチャ */
function usecase(uc: string, criteria: string[], headingLevel = "##"): string {
  return [
    `${headingLevel} ${uc}: ユースケース ${uc}`,
    "",
    "### 正常系フロー",
    "| # | アクター | アクション |",
    "|---|----------|-----------|",
    "| 1 | 利用者 | 操作する |",
    "",
    "### 受け入れ基準",
    ...criteria,
    "",
  ].join("\n");
}

Deno.test("checkAcCoverage_with_every_story_covered_in_its_realizing_uc_returns_no_errors", () => {
  const userStories = stories([
    { id: "US-001", realizes: "UC-001" },
    { id: "US-002", realizes: "UC-001, UC-002" },
  ]);
  const usecases = "# ユースケース記述\n\n" +
    usecase("UC-001", ["- [ ] （US-001）a", "- [ ] （US-002）b"]) +
    usecase("UC-002", ["- [ ] （US-002）c"]);

  assertEquals(checkAcCoverage(userStories, usecases), []);
});

Deno.test("checkAcCoverage_with_story_missing_from_criteria_reports_it_as_uncovered", () => {
  const userStories = stories([
    { id: "US-001", realizes: "UC-001" },
    { id: "US-002", realizes: "UC-001" },
  ]);
  const usecases = usecase("UC-001", ["- [ ] （US-001）a"]);

  assertEquals(checkAcCoverage(userStories, usecases), [
    "NG US-002: 受け入れ基準に現れない",
  ]);
});

Deno.test("checkAcCoverage_with_story_only_in_flow_table_does_not_count_it_as_covered", () => {
  const userStories = stories([{ id: "US-001", realizes: "UC-001" }]);
  const usecases = [
    "## UC-001: ユースケース",
    "| # | アクター | アクション |",
    "| 1 | 利用者 | （US-001）を満たす操作をする |",
    "",
  ].join("\n");

  assertEquals(checkAcCoverage(userStories, usecases), [
    "NG US-001: 受け入れ基準に現れない",
  ]);
});

Deno.test("checkAcCoverage_with_checked_criteria_counts_them_as_covered", () => {
  const userStories = stories([{ id: "US-001", realizes: "UC-001" }]);
  const usecases = usecase("UC-001", ["- [x] （US-001）a"]);

  assertEquals(checkAcCoverage(userStories, usecases), []);
});

Deno.test("checkAcCoverage_with_uc_heading_at_level_three_attributes_bold_subsections_to_it", () => {
  const userStories = stories([{ id: "US-001", realizes: "UC-001" }]);
  const usecases = [
    "## 5. ユースケース記述",
    "",
    "### UC-001: 空き車両を確認する",
    "",
    "**受け入れ基準**",
    "",
    "- [ ] （US-001）a",
    "",
  ].join("\n");

  assertEquals(checkAcCoverage(userStories, usecases), []);
});

Deno.test("checkAcCoverage_with_criteria_outside_any_uc_section_reports_the_line_and_the_story", () => {
  const userStories = stories([
    { id: "US-001", realizes: "UC-001" },
    { id: "US-002", realizes: "静的ページ「ご利用方法」" },
  ]);
  const usecases = [
    "### UC-001: ユースケース",
    "- [ ] （US-001）a",
    "### 静的ページの受け入れ基準",
    "- [ ] （US-002）b",
    "",
  ].join("\n");

  assertEquals(checkAcCoverage(userStories, usecases), [
    "NG US-002: 実現するユースケース行に UC 番号が無い",
    "NG US-002: 受け入れ基準に現れない",
    "NG USECASES.md:4: 受け入れ基準がユースケースの節の外にある",
  ]);
});

Deno.test("checkAcCoverage_with_realizing_line_missing_reports_it", () => {
  const userStories = stories([{ id: "US-001", realizes: null }]);
  const usecases = usecase("UC-001", ["- [ ] （US-001）a"]);

  assertEquals(checkAcCoverage(userStories, usecases), [
    "NG US-001: 実現するユースケース行が無い",
  ]);
});

Deno.test("checkAcCoverage_with_realizing_line_disagreeing_with_criteria_reports_both_sets", () => {
  const userStories = stories([{ id: "US-001", realizes: "UC-001, UC-002" }]);
  const usecases = usecase("UC-001", []) +
    usecase("UC-002", []) +
    usecase("UC-003", ["- [ ] （US-001）a"]);

  assertEquals(checkAcCoverage(userStories, usecases), [
    "NG US-001: 実現するユースケース (UC-001, UC-002) と受け入れ基準の UC (UC-003) が一致しない",
  ]);
});

Deno.test("checkAcCoverage_with_several_criteria_per_uc_and_unordered_realizing_line_treats_them_as_sets", () => {
  const userStories = stories([{ id: "US-001", realizes: "UC-002, UC-001, UC-002" }]);
  const usecases = usecase("UC-001", [
    "- [ ] （US-001）a",
    "- [ ] （US-001）b",
    "- [ ] （US-001）c",
  ]) + usecase("UC-002", ["- [ ] （US-001）d", "- [ ] （US-001）e"]);

  assertEquals(checkAcCoverage(userStories, usecases), []);
});

Deno.test("checkAcCoverage_with_wont_story_written_as_heading_reports_it_as_uncovered", () => {
  const userStories = stories(
    [{ id: "US-001", realizes: "UC-001" }],
    "#### US-002: やらないストーリー\n\n- **開発者として**\n",
  );
  const usecases = usecase("UC-001", ["- [ ] （US-001）a"]);

  assertEquals(checkAcCoverage(userStories, usecases), [
    "NG US-002: 実現するユースケース行が無い",
    "NG US-002: 受け入れ基準に現れない",
  ]);
});

Deno.test("checkAcCoverage_with_story_heading_not_at_level_four_does_not_treat_it_as_a_story", () => {
  const userStories = stories([{ id: "US-001", realizes: "UC-001" }]) +
    "\n### US-002: 見出しレベルが違う\n";
  const usecases = usecase("UC-001", ["- [ ] （US-001）a", "- [ ] （US-002）b"]);

  assertEquals(checkAcCoverage(userStories, usecases), [
    "NG USECASES.md:10: US-002 が USER_STORIES.md に無い",
  ]);
});

Deno.test("checkAcCoverage_with_uc_id_not_at_start_of_heading_does_not_open_a_uc_section", () => {
  const userStories = stories([{ id: "US-001", realizes: "UC-001" }]);
  const usecases = [
    "## 補足: UC-001 の背景",
    "- [ ] （US-001）a",
    "",
  ].join("\n");

  assertEquals(checkAcCoverage(userStories, usecases), [
    "NG US-001: 受け入れ基準に現れない",
    "NG USECASES.md:2: 受け入れ基準がユースケースの節の外にある",
  ]);
});

Deno.test("checkAcCoverage_with_criteria_naming_an_unknown_story_reports_the_line", () => {
  const userStories = stories([{ id: "US-001", realizes: "UC-001" }]);
  const usecases = usecase("UC-001", ["- [ ] （US-001）a", "- [ ] （US-099）b"]);

  assertEquals(checkAcCoverage(userStories, usecases), [
    "NG USECASES.md:10: US-099 が USER_STORIES.md に無い",
  ]);
});

Deno.test("checkAcCoverage_with_realizing_line_after_next_heading_does_not_attribute_it_to_previous_story", () => {
  const userStories = [
    "#### US-001: a",
    "**エピック**: E1",
    "### Should（重要）",
    "**実現するユースケース**: UC-001",
    "",
  ].join("\n");
  const usecases = usecase("UC-001", ["- [ ] （US-001）a"]);

  assertEquals(checkAcCoverage(userStories, usecases), [
    "NG US-001: 実現するユースケース行が無い",
  ]);
});

Deno.test("cli_with_uncovered_story_prints_errors_and_exits_1", async () => {
  const dir = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(
      `${dir}/USER_STORIES.md`,
      stories([{ id: "US-001", realizes: "UC-001" }]),
    );
    await Deno.writeTextFile(`${dir}/USECASES.md`, usecase("UC-001", []));
    const { code, stdout } = await new Deno.Command(Deno.execPath(), {
      args: [
        "run",
        "--allow-read",
        new URL("./check-ac-coverage.ts", import.meta.url).pathname,
        `${dir}/USER_STORIES.md`,
        `${dir}/USECASES.md`,
      ],
      stdout: "piped",
    }).output();

    assertEquals(
      { code, stdout: new TextDecoder().decode(stdout) },
      { code: 1, stdout: "NG US-001: 受け入れ基準に現れない\n" },
    );
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("cli_with_full_coverage_prints_nothing_and_exits_0", async () => {
  const dir = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(
      `${dir}/USER_STORIES.md`,
      stories([{ id: "US-001", realizes: "UC-001" }]),
    );
    await Deno.writeTextFile(`${dir}/USECASES.md`, usecase("UC-001", ["- [ ] （US-001）a"]));
    const { code, stdout } = await new Deno.Command(Deno.execPath(), {
      args: [
        "run",
        "--allow-read",
        new URL("./check-ac-coverage.ts", import.meta.url).pathname,
        `${dir}/USER_STORIES.md`,
        `${dir}/USECASES.md`,
      ],
      stdout: "piped",
    }).output();

    assertEquals({ code, stdout: new TextDecoder().decode(stdout) }, { code: 0, stdout: "" });
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
