import { assertEquals } from "jsr:@std/assert";
import { checkLayers } from "./layer-check.ts";

// レイヤ境界違反 (内側の層が外側の層を import している) は「import 文の向き」という
// 機械的な性質なので、目視ではなく決定的に判定する。実測では LLM に import 行を
// 読ませていたとき、型のみの cross-layer import 1 行を 5 回中 4 回見落としながら
// 毎回「違反なし」を返していた。ここではその判定を pin する。

const CONFIG = {
  inner: ["src/domain/", "src/usecase/"],
  outer: ["src/infra/", "src/web/"],
};

Deno.test("checkLayers_with_inner_importing_outer_reports_a_violation", () => {
  const result = checkLayers([{
    path: "src/domain/revision.ts",
    content: 'import { save } from "../infra/repository/map.ts";\n',
  }], CONFIG);

  assertEquals(result, {
    ok: false,
    skip_reason: null,
    violations: [{
      file: "src/domain/revision.ts",
      line: 1,
      rule: "clean_arch_layer",
      severity: "high",
      message:
        'src/domain/revision.ts:1 (inner) が outer の src/infra/repository/map.ts を import している: import { save } from "../infra/repository/map.ts";',
      fix_proposal:
        "inner に Port (interface) を定義し、outer に Adapter 実装を置いて DI で繋ぐ",
    }],
    checked_file_list: [{
      file: "src/domain/revision.ts",
      layer: "inner",
      import_lines_checked: 1,
      violation_count: 1,
    }],
  });
});

// 実測で見落とされていた当のケース。型のみの import も実行時の依存は無くとも
// 設計上の依存方向を逆転させるので違反として扱う。
Deno.test("checkLayers_with_a_type_only_import_across_layers_reports_a_violation", () => {
  const result = checkLayers([{
    path: "src/domain/revision.ts",
    content:
      'import type { RevisionDiff } from "../infra/repository/map.ts";\n',
  }], CONFIG);

  assertEquals(result.violations.length, 1);
  assertEquals(result.violations[0].line, 1);
  assertEquals(result.ok, false);
});

Deno.test("checkLayers_with_inner_importing_inner_reports_no_violation", () => {
  const result = checkLayers([{
    path: "src/usecase/move-node.ts",
    content: 'import { Node } from "../domain/node.ts";\n',
  }], CONFIG);

  assertEquals(result, {
    ok: true,
    skip_reason: null,
    violations: [],
    checked_file_list: [{
      file: "src/usecase/move-node.ts",
      layer: "inner",
      import_lines_checked: 1,
      violation_count: 0,
    }],
  });
});

Deno.test("checkLayers_with_outer_importing_inner_reports_no_violation", () => {
  const result = checkLayers([{
    path: "src/infra/repository/map.ts",
    content: 'import { Node } from "../../domain/node.ts";\n',
  }], CONFIG);

  assertEquals(result.violations, []);
  assertEquals(result.checked_file_list[0].layer, "outer");
});

// 「違反が無い」と「そのファイルを見ていない」を呼び出し側が区別できるように、
// violation_count: 0 のファイルも必ず一覧に載せる。
Deno.test("checkLayers_lists_every_inspected_file_including_clean_ones", () => {
  const result = checkLayers([
    { path: "src/domain/a.ts", content: 'import { b } from "./b.ts";\n' },
    {
      path: "src/domain/c.ts",
      content: 'import { d } from "../infra/d.ts";\n',
    },
  ], CONFIG);

  assertEquals(
    result.checked_file_list.map((f) => [f.file, f.violation_count]),
    [
      ["src/domain/a.ts", 0],
      ["src/domain/c.ts", 1],
    ],
  );
});

Deno.test("checkLayers_with_a_file_outside_every_layer_marks_it_unknown_and_skips_judgement", () => {
  const result = checkLayers([{
    path: "scripts/seed.ts",
    content: 'import { save } from "../src/infra/repository/map.ts";\n',
  }], CONFIG);

  assertEquals(result.violations, []);
  assertEquals(result.checked_file_list[0].layer, "unknown");
});

Deno.test("checkLayers_with_no_layer_patterns_skips_and_says_why", () => {
  const result = checkLayers([{
    path: "src/a.ts",
    content: 'import "./b.ts";\n',
  }], {
    inner: [],
    outer: [],
  });

  assertEquals(result, {
    ok: true,
    skip_reason: "no_layer_convention",
    violations: [],
    checked_file_list: [],
  });
});

// bare specifier (エイリアス・モジュールパス) もパターンに当たれば判定する
Deno.test("checkLayers_with_a_bare_specifier_matching_an_outer_pattern_reports_a_violation", () => {
  const result = checkLayers([{
    path: "src/domain/revision.ts",
    content: 'import { db } from "@/src/infra/d1.ts";\n',
  }], CONFIG);

  assertEquals(result.violations.length, 1);
});

Deno.test("checkLayers_counts_every_import_line_it_read", () => {
  const result = checkLayers([{
    path: "src/domain/a.ts",
    content: [
      'import { b } from "./b.ts";',
      "const x = 1;",
      'import type { C } from "./c.ts";',
      'export { d } from "./d.ts";',
    ].join("\n"),
  }], CONFIG);

  assertEquals(result.checked_file_list[0].import_lines_checked, 3);
});

// 言語ごとに import の書式が違うので、それぞれの形で cross-layer を検出できること
Deno.test("checkLayers_detects_cross_layer_imports_in_go_rust_python_and_lua", () => {
  const result = checkLayers([
    { path: "src/domain/a.go", content: '\t"example.com/app/src/infra/db"\n' },
    { path: "src/domain/b.rs", content: "use crate::src::infra::db;\n" },
    { path: "src/domain/c.py", content: "from src.infra.db import save\n" },
    {
      path: "src/domain/d.lua",
      content: 'local db = require("src.infra.db")\n',
    },
  ], {
    inner: ["src/domain/"],
    outer: ["src/infra/", "src::infra", "src.infra"],
  });

  assertEquals(result.violations.map((v) => v.file), [
    "src/domain/a.go",
    "src/domain/b.rs",
    "src/domain/c.py",
    "src/domain/d.lua",
  ]);
});

// 最長一致で層を決める。inner の下に outer 名のディレクトリがある構成で誤判定しない
Deno.test("checkLayers_classifies_by_the_longest_matching_pattern", () => {
  const result = checkLayers([{
    path: "src/domain/infra/policy.ts",
    content: 'import { x } from "../node.ts";\n',
  }], { inner: ["src/domain/"], outer: ["src/domain/infra/"] });

  assertEquals(result.checked_file_list[0].layer, "outer");
  assertEquals(result.violations, []);
});
