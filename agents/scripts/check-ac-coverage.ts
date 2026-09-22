#!/usr/bin/env -S deno run --allow-read
/**
 * dev-spec の受け入れ基準の被覆を検査する。
 *
 * 受け入れ基準はユースケース (USECASES.md) の節の中に `- [ ] （US-<番号>）…` の形で置き、
 * ストーリー (USER_STORIES.md) は `**実現するユースケース**: UC-<番号>, …` の 1 行で
 * ユースケースを指す。この 2 つが食い違わないことを確かめる。
 *
 * 検査すること:
 * - `#### US-<番号>` 見出しのストーリーごとに、「実現するユースケース」行があり UC 番号を含むか
 * - そのストーリーの受け入れ基準が、いずれかの UC の節の中に 1 行以上あるか
 * - 受け入れ基準が現れる UC の集合と、「実現するユースケース」行の UC の集合が一致するか
 * - 受け入れ基準の行が UC の節の外に無いか、USER_STORIES.md に無い番号を指していないか
 *
 * シェルの 1 行コマンドで書くと、bash では `（$id）` の `$id` が全角括弧の先頭バイトまで
 * 変数名として読まれて空になり、全ストーリーが NG になる。その事故を避けるためにスクリプトにした。
 *
 * 使い方:
 *   check-ac-coverage.ts <USER_STORIES.md> <USECASES.md>
 * NG を 1 行ずつ出力して exit 1。問題が無ければ何も出力せず exit 0。
 */

const STORY_HEADING = /^#### (US-\d+)\b/;
const REALIZES_LINE = /^\*\*実現するユースケース\*\*:(.*)$/;
const HEADING = /^(#{1,6}) (.*)$/;
const UC_ID = /UC-\d+/g;
const CRITERION = /^- \[[ xX]\] （(US-\d+)）/;

type StoryRealizes = { id: string; realizes: string[] | null };

/** ストーリーごとの「実現するユースケース」の UC 一覧。行が無ければ null */
function parseStories(userStories: string): StoryRealizes[] {
  const result: StoryRealizes[] = [];
  let current: StoryRealizes | null = null;
  for (const line of userStories.split("\n")) {
    const story = line.match(STORY_HEADING);
    if (story) {
      current = { id: story[1], realizes: null };
      result.push(current);
      continue;
    }
    const heading = line.match(HEADING);
    if (heading && heading[1].length <= 4) {
      current = null;
      continue;
    }
    const realizes = line.match(REALIZES_LINE);
    if (realizes && current) {
      current.realizes = realizes[1].match(UC_ID) ?? [];
    }
  }
  return result;
}

type Criterion = { story: string; uc: string | null; lineNumber: number };

/** 受け入れ基準の行と、それが属する UC。UC の節の外なら uc は null */
function parseCriteria(usecases: string): Criterion[] {
  const result: Criterion[] = [];
  let uc: string | null = null;
  let ucLevel = 0;
  usecases.split("\n").forEach((line, index) => {
    const heading = line.match(HEADING);
    if (heading) {
      const level = heading[1].length;
      const ucId = heading[2].match(/^(UC-\d+)\b/);
      if (ucId) {
        uc = ucId[1];
        ucLevel = level;
      } else if (level <= ucLevel) {
        uc = null;
        ucLevel = 0;
      }
      return;
    }
    const criterion = line.match(CRITERION);
    if (criterion) result.push({ story: criterion[1], uc, lineNumber: index + 1 });
  });
  return result;
}

function uniqueSorted(values: string[]): string[] {
  return [...new Set(values)].sort();
}

export function checkAcCoverage(userStories: string, usecases: string): string[] {
  const stories = parseStories(userStories);
  const criteria = parseCriteria(usecases);
  const errors: string[] = [];

  for (const { id, realizes } of stories) {
    const criteriaUcs = uniqueSorted(
      criteria.filter((c) => c.story === id && c.uc !== null).map((c) => c.uc as string),
    );
    if (realizes === null) {
      errors.push(`NG ${id}: 実現するユースケース行が無い`);
    } else if (realizes.length === 0) {
      errors.push(`NG ${id}: 実現するユースケース行に UC 番号が無い`);
    }
    if (criteriaUcs.length === 0) {
      errors.push(`NG ${id}: 受け入れ基準に現れない`);
      continue;
    }
    const realizesUcs = uniqueSorted(realizes ?? []);
    if (realizesUcs.length > 0 && realizesUcs.join(", ") !== criteriaUcs.join(", ")) {
      errors.push(
        `NG ${id}: 実現するユースケース (${realizesUcs.join(", ")}) と受け入れ基準の UC (${
          criteriaUcs.join(", ")
        }) が一致しない`,
      );
    }
  }

  const known = new Set(stories.map((s) => s.id));
  for (const { story, uc, lineNumber } of criteria) {
    if (uc === null) {
      errors.push(`NG USECASES.md:${lineNumber}: 受け入れ基準がユースケースの節の外にある`);
    } else if (!known.has(story)) {
      errors.push(`NG USECASES.md:${lineNumber}: ${story} が USER_STORIES.md に無い`);
    }
  }
  return errors;
}

if (import.meta.main) {
  const [userStoriesPath, usecasesPath] = Deno.args;
  if (!userStoriesPath || !usecasesPath) {
    console.error("使い方: check-ac-coverage.ts <USER_STORIES.md> <USECASES.md>");
    Deno.exit(2);
  }
  const errors = checkAcCoverage(
    await Deno.readTextFile(userStoriesPath),
    await Deno.readTextFile(usecasesPath),
  );
  for (const error of errors) console.log(error);
  Deno.exit(errors.length === 0 ? 0 : 1);
}
