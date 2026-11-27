#!/bin/sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../cross-product.sh"
# shellcheck source=../../../dev-spec/scripts/tests/assert.sh
. "$HERE/../../../dev-spec/scripts/tests/assert.sh"

setup() {
  R="$T/repo"
  git init -q "$R"
  git -C "$R" config user.email t@example.com
  git -C "$R" config user.name t
  git -C "$R" config commit.gpgsign false
  : >"$R/.keep"
  B=$(commit)
}

commit() {
  git -C "$R" add -A
  git -C "$R" commit -q -m c
  git -C "$R" rev-parse HEAD
}

run() { ${SH:-sh} "$SCRIPT" "$R" "$B" >"$T/out" 2>"$T/err"; CODE=$?; }

write() { mkdir -p "$(dirname "$R/$1")" && cat >"$R/$1"; }

expect_found() {
  assert_eq 1 "$CODE"
  printf '%s\n' "$@" >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

expect_none() {
  assert_eq 0 "$CODE"
  : >"$T/want"
  assert_file_eq "$T/want" "$T/out"
}

test_js_each_with_flatmap_table() {
  setup
  write a.test.ts <<'EOF'
import { it } from "vitest";

it.each(
  ["a", "b"].flatMap((x) => [1, 2].map((n) => ({ x, n }))),
)("$x $n", ({ x, n }) => {
  expect(f(x, n)).toBe(1);
});
EOF
  run
  expect_found "$(printf 'a.test.ts:3\teach-generated')"
}

test_js_each_with_nested_map_table() {
  setup
  write a.spec.tsx <<'EOF'
test.each(["a", "b"].map((x) => [1, 2].map((n) => [x, n])).flat())("%s", (x) => {
  run(x);
});
EOF
  run
  expect_found "$(printf 'a.spec.tsx:1\teach-generated')"
}

test_js_each_with_generated_table_variable() {
  setup
  write a.test.js <<'EOF'
const cases = ["a", "b"].flatMap((x) =>
  [1, 2].map((n) => ({ x, n })),
);

it.each(cases)("$x", ({ x }) => {
  run(x);
});
EOF
  run
  expect_found "$(printf 'a.test.js:5\teach-generated')"
}

test_js_each_with_spread_of_generated_table() {
  setup
  write a.test.ts <<'EOF'
const shifted = keys.flatMap((k) => mods.map((m) => `<${m}-${k}>`));
const plain = ["a", "b"];
it.each([...plain, ...shifted])("%s", (k) => {
  run(k);
});
EOF
  run
  expect_found "$(printf 'a.test.ts:3\teach-generated')"
}

test_js_nested_loops_on_one_line() {
  setup
  write a.test.ts <<'EOF'
modes.forEach((m) => keys.forEach((k) => {
  it(`${m}${k}`, () => run(m, k));
}));
for (const m of modes) for (const k of keys) it(`${m}${k}`, () => run(m, k));
for (const m of modes) { for (const k of keys) { it(`${m}${k}`, () => run(m, k)); } }
EOF
  run
  expect_found "$(printf 'a.test.ts:1\tnested-loop')" "$(printf 'a.test.ts:4\tnested-loop')" "$(printf 'a.test.ts:5\tnested-loop')"
}

test_js_each_inside_loop_and_loop_inside_describe_each() {
  setup
  write a.test.ts <<'EOF'
for (const mode of modes) {
  it.each(keys)("%s", (key) => run(mode, key));
}
describe.each(modes)("%s", (mode) => {
  for (const key of keys) {
    it(key, () => run(mode, key));
  }
});
EOF
  run
  expect_found "$(printf 'a.test.ts:1\tnested-loop')" "$(printf 'a.test.ts:4\tnested-loop')"
}

test_js_table_pushed_in_nested_loops() {
  setup
  write a.test.ts <<'EOF'
const cases = [];
for (const mode of modes) {
  for (const key of keys) {
    cases.push({ mode, key });
  }
}
it.each(cases)("$mode", ({ mode, key }) => run(mode, key));
EOF
  run
  expect_found "$(printf 'a.test.ts:7\teach-generated')"
}

test_js_test_for_with_generated_table() {
  setup
  write a.test.ts <<'EOF'
test.for(modes.flatMap((m) => keys.map((k) => [m, k])))("%s", ([m, k]) => {
  run(m, k);
});
EOF
  run
  expect_found "$(printf 'a.test.ts:1\teach-generated')"
}

test_js_change_only_in_generated_table_definition_is_reported() {
  setup
  write a.test.ts <<'EOF'
const cases = modes.flatMap((m) => keys.map((k) => ({ m, k })));

it.each(cases)("$m", ({ m, k }) => run(m, k));
EOF
  B=$(commit)
  write a.test.ts <<'EOF'
const cases = modes.flatMap((m) => keys.map((k) => ({ m, k, extra: true })));

it.each(cases)("$m", ({ m, k }) => run(m, k));
EOF
  run
  expect_found "$(printf 'a.test.ts:3\teach-generated')"
}

test_js_reason_above_generated_table_definition_exempts() {
  setup
  write a.test.ts <<'EOF'
// cross-product: src/a.ts:3 が m と k を同じ分岐で読む
const cases = modes.flatMap((m) => keys.map((k) => ({ m, k })));
const other = 1;
const more = 2;

it.each(cases)("$m", ({ m, k }) => run(m, k));
EOF
  run
  expect_none
}

test_exempted_blocks_are_listed_on_stderr() {
  setup
  write a.test.ts <<'EOF'
// cross-product: src/a.ts:12 が mode と key を同じ分岐で読む
it.each(["n", "v"].flatMap((m) => ["h", "j"].map((k) => ({ m, k }))))("$m", ({ m, k }) => {
  run(m, k);
});
EOF
  run
  expect_none
  printf 'a.test.ts:2\texempt\tsrc/a.ts:12\n' >"$T/want_err"
  assert_file_eq "$T/want_err" "$T/err"
}

test_js_hierarchical_and_single_list_expansions_are_not_products() {
  setup
  write a.test.ts <<'EOF'
for (const group of groups) {
  for (const c of group.cases) {
    it(c.name, () => run(c));
  }
}
it.each(groups.flatMap((g) => g.cases))("$name", (c) => run(c));
it.each(limits.flatMap((n) => [n, n + 1]))("%i", (n) => run(n));
it.each(groups.flatMap((g) => g.cases.map((c) => ({ ...c, g: g.name }))))("$name", (c) => run(c));
describe.each(groups)("$name", (g) => {
  it.each(g.cases)("$name", (c) => run(c));
});
EOF
  run
  expect_none
}

test_go_nested_three_clause_loops() {
  setup
  write a_test.go <<'EOF'
package a

func TestConflict(t *testing.T) {
	for i := 0; i < len(modes); i++ {
		for j := 0; j < len(keys); j++ {
			t.Run(modes[i]+keys[j], func(t *testing.T) {
				check(t, modes[i], keys[j])
			})
		}
	}
}
EOF
  run
  expect_found "$(printf 'a_test.go:4\tnested-loop')"
}

test_go_hierarchical_range_and_non_subtest_run_are_not_products() {
  setup
  write a_test.go <<'EOF'
package a

func TestGroups(t *testing.T) {
	for _, tt := range tests {
		for _, sub := range tt.subs {
			t.Run(sub.name, func(t *testing.T) {
				check(t, sub)
			})
		}
	}
	for _, a := range as {
		for _, b := range bs {
			if err := exec.Command(a, b).Run(); err != nil {
				t.Fatal(err)
			}
		}
	}
}
EOF
  run
  expect_none
}

test_js_flatmap_with_array_from_is_a_product() {
  setup
  write a.test.ts <<'EOF'
it.each(keys.flatMap((k) => Array.from({ length: 8 }, (_, mask) => ({ k, mask }))))("$k", ({ k, mask }) => {
  run(k, mask);
});
EOF
  run
  expect_found "$(printf 'a.test.ts:1\teach-generated')"
}

test_js_multiline_forms() {
  setup
  write a.test.ts <<'EOF'
for (const m of modes)
  for (const k of keys)
    it(`${m}${k}`, () => run(m, k));
const cases = modes
  .flatMap((m) => keys.map((k) => ({ m, k })))
  .filter((c) => c.m !== "x");
test.each(cases)("$m", ({ m, k }) => run(m, k));
it.each(Array.from({ length: 3 }, (_, i) => Array.from({ length: 4 }, (_, j) => [i, j])).flat())("%i", (i, j) => run(i, j));
EOF
  run
  expect_found "$(printf 'a.test.ts:1\tnested-loop')" "$(printf 'a.test.ts:7\teach-generated')" "$(printf 'a.test.ts:8\teach-generated')"
}

test_js_sibling_loops_are_not_products() {
  setup
  write a.test.ts <<'EOF'
for (const a of as) { it(a, () => run(a)); } for (const b of bs) { it(b, () => run(b)); }
as.forEach((a) => it(a, () => run(a))); bs.forEach((b) => it(b, () => run(b)));
for (const a of as) it(a, () => run(a)); for (const b of bs) it(b, () => run(b));
for (const a of as)
  it(a, () => run(a));
for (const b of bs)
  it(b, () => run(b));
if (cond) for (const a of as) it(a, () => run(a));
else for (const b of bs) it(b, () => run(b));
if (cond)
	for (const m of modes)
		if (m === "x") it(m, () => run(m));
		else it(`${m}!`, () => run2(m));
else for (const b of bs) it(b, () => run(b));
EOF
  run
  expect_none
}

test_js_same_variable_name_in_other_describe() {
  setup
  write a.test.ts <<'EOF'
describe("a", () => {
  // cross-product: src/a.ts:3 が m と k を同じ分岐で読む
  const cases = modes.flatMap((m) => keys.map((k) => ({ m, k })));
  it.each(cases)("$m", ({ m, k }) => run(m, k));
});
describe("b", () => {
  const cases = [{ m: "n" }, { m: "v" }];
  it.each(cases)("$m", ({ m }) => run(m));
});
EOF
  run
  expect_none
  printf 'a.test.ts:4\texempt\tsrc/a.ts:3\n' >"$T/want_err"
  assert_file_eq "$T/want_err" "$T/err"
}

test_js_generated_table_defined_inside_describe() {
  setup
  write a.test.ts <<'EOF'
describe("outer", () => {
  const cases = modes.flatMap((m) => keys.map((k) => ({ m, k })));
  describe("inner", () => {
    it.each(cases)("$m", ({ m, k }) => run(m, k));
  });
});
EOF
  run
  expect_found "$(printf 'a.test.ts:4\teach-generated')"
}

test_js_braceless_nesting_with_conditions() {
  setup
  write a.test.ts <<'EOF'
for (const m of modes)
  for (const k of keys)
    if (k !== m)
      it(`${m}${k}`, () => run(m, k));
for (const m of modes)
  if (m !== "x") for (const k of keys)
    it(`${m}${k}`, () => run(m, k));
for (const m of modes)
  if (m === "x") it(m, () => run(m));
  else for (const k of keys) it(`${m}${k}`, () => run(m, k));
for (const a of as)
  for (const b of bs)
    for (const c of cs)
      it(`${a}${b}${c}`, () => run(a, b, c));
for (const m of modes)
  if (m === "x") it(m, () => run(m));
  else
    for (const k of keys)
      it(`${m}${k}`, () => run(m, k));
for (const m of modes)
  if (m === "x") it(m, () => run(m));
  else if (m === "y")
    it(m, () => run(m));
  else
    for (const k of keys)
      it(`${m}${k}`, () => run(m, k));
for (const m of modes)
  if (m === "x") it(m, () => run(m))
  else
    for (const k of keys)
      it(`${m}${k}`, () => run(m, k))
for (const m of modes)
  if (m === "x") it(m, () => run(m))
  else if (m === "y") it(m, () => run(m))
  else for (const k of keys) it(`${m}${k}`, () => run(m, k))
EOF
  run
  expect_found "$(printf 'a.test.ts:1\tnested-loop')" "$(printf 'a.test.ts:5\tnested-loop')" "$(printf 'a.test.ts:8\tnested-loop')" "$(printf 'a.test.ts:11\tnested-loop')" "$(printf 'a.test.ts:15\tnested-loop')" "$(printf 'a.test.ts:20\tnested-loop')" "$(printf 'a.test.ts:27\tnested-loop')" "$(printf 'a.test.ts:32\tnested-loop')"
}

test_js_generated_table_with_line_break_or_type_annotation() {
  setup
  write a.test.ts <<'EOF'
const cases =
  modes.flatMap((m) => keys.map((k) => ({ m, k })));
it.each(cases)("$m", ({ m, k }) => run(m, k));
const typed: Case[] = modes.flatMap((m) => keys.map((k) => ({ m, k })));
it.each(typed)("$m", ({ m, k }) => run(m, k));
const fn: (x: number) => Case[] = (x) => [];
EOF
  run
  expect_found "$(printf 'a.test.ts:3\teach-generated')" "$(printf 'a.test.ts:5\teach-generated')"
}

test_go_subtest_name_with_comma() {
  setup
  write a_test.go <<'EOF'
package a

func TestConflict(t *testing.T) {
	for _, mode := range modes {
		for _, key := range keys {
			t.Run(fmt.Sprintf("%s-%s", mode, key), func(t *testing.T) {
				check(t, mode, key)
			})
		}
	}
	for _, a := range as {
		for _, b := range bs {
			t.Run(
				a+b,
				func(t *testing.T) { check(t, a, b) },
			)
		}
	}
}
EOF
  run
  expect_found "$(printf 'a_test.go:4\tnested-loop')" "$(printf 'a_test.go:11\tnested-loop')"
}

test_js_describe_each_containing_each() {
  setup
  write a.test.ts <<'EOF'
describe.each(["normal", "visual"])("%s", (mode) => {
  it.each(["h", "j"])("%s", (key) => {
    expect(conflict(mode, key)).toEqual([]);
  });
});
EOF
  run
  expect_found "$(printf 'a.test.ts:1\tdescribe-each-nested')"
}

test_js_nested_loops_around_test() {
  setup
  write a.test.ts <<'EOF'
for (const mode of modes) {
  for (const key of keys) {
    it(`${mode} ${key}`, () => {
      expect(conflict(mode, key)).toEqual([]);
    });
  }
}
EOF
  run
  expect_found "$(printf 'a.test.ts:1\tnested-loop')"
}

test_js_plain_table_and_single_loop_are_not_products() {
  setup
  write a.test.ts <<'EOF'
it.each([
  ["a", 1],
  ["b", 2],
])("%s", (x, n) => {
  expect(f(x)).toBe(n);
});
for (const key of keys) {
  it(key, () => {
    expect(parse(key)).not.toBeNull();
  });
}
const labels = ["a", "b"].map((x) => x.toUpperCase());
it.each(labels)("%s", (x) => {
  expect(x).toBe(x);
});
EOF
  run
  expect_none
}

test_js_words_inside_strings_and_comments_are_ignored() {
  setup
  write a.test.ts <<'EOF'
it.each(["flatMap(", "a.map(b.map("])("%s", (x) => {
  // ["a"].flatMap((x) => x)
  expect(x).toBe(`.map(.map(`);
});
EOF
  run
  expect_none
}

test_js_reason_with_location_exempts_block() {
  setup
  write a.test.ts <<'EOF'
// cross-product: src/a.ts:12 が mode と key を同じ分岐で読む
it.each(["n", "v"].flatMap((m) => ["h", "j"].map((k) => ({ m, k }))))("$m", ({ m, k }) => {
  run(m, k);
});
EOF
  run
  expect_none
}

test_js_reason_without_location_does_not_exempt() {
  setup
  write a.test.ts <<'EOF'
// cross-product: 念のため全部
it.each(["n", "v"].flatMap((m) => ["h", "j"].map((k) => ({ m, k }))))("$m", ({ m, k }) => {
  run(m, k);
});
EOF
  run
  expect_found "$(printf 'a.test.ts:2\teach-generated')"
}

test_only_blocks_touched_by_the_diff_are_reported() {
  setup
  write a.test.ts <<'EOF'
it.each(["n", "v"].flatMap((m) => ["h", "j"].map((k) => ({ m, k }))))("$m", ({ m, k }) => {
  run(m, k);
});

it("other", () => {
  expect(1).toBe(1);
});
EOF
  B=$(commit)
  write a.test.ts <<'EOF'
it.each(["n", "v"].flatMap((m) => ["h", "j"].map((k) => ({ m, k }))))("$m", ({ m, k }) => {
  run(m, k);
});

it("other", () => {
  expect(2).toBe(2);
});
EOF
  run
  expect_none
}

test_row_added_to_existing_product_is_reported() {
  setup
  write a.test.ts <<'EOF'
it.each(["n", "v"].flatMap((m) => ["h", "j"].map((k) => ({ m, k }))))("$m", ({ m, k }) => {
  run(m, k);
});
EOF
  B=$(commit)
  write a.test.ts <<'EOF'
it.each(["n", "v", "t"].flatMap((m) => ["h", "j"].map((k) => ({ m, k }))))("$m", ({ m, k }) => {
  run(m, k);
});
EOF
  run
  expect_found "$(printf 'a.test.ts:1\teach-generated')"
}

test_non_test_files_are_ignored() {
  setup
  write src/a.ts <<'EOF'
for (const a of as) {
  for (const b of bs) {
    test(a, b);
  }
}
EOF
  write src/a.go <<'EOF'
package a

func f() {
	for _, a := range as {
		for _, b := range bs {
			t.Run(a+b, nil)
		}
	}
}
EOF
  run
  expect_none
}

test_go_nested_range_around_subtest() {
  setup
  write a_test.go <<'EOF'
package a

func TestConflict(t *testing.T) {
	for _, mode := range modes {
		for _, key := range keys {
			t.Run(mode+key, func(t *testing.T) {
				if got := conflict(mode, key); got != nil {
					t.Fatal(got)
				}
			})
		}
	}
}
EOF
  run
  expect_found "$(printf 'a_test.go:4\tnested-loop')"
}

test_go_table_built_by_nested_range() {
  setup
  write a_test.go <<'EOF'
package a

func TestConflict(t *testing.T) {
	var tests []tc
	for _, mode := range modes {
		for _, key := range keys {
			tests = append(tests, tc{mode, key})
		}
	}
	for _, tt := range tests {
		t.Run(tt.mode, func(t *testing.T) {
			check(t, tt)
		})
	}
}
EOF
  run
  expect_found "$(printf 'a_test.go:5\tgo-append-table')"
}

test_go_data_built_by_nested_range_without_subtests() {
  setup
  write a_test.go <<'EOF'
package a

func TestArchive(t *testing.T) {
	for _, version := range versions {
		t.Run(version, func(t *testing.T) {
			var snaps []snap
			for _, intent := range intents {
				snaps = append(snaps, take(intent))
			}
			for _, s := range snaps {
				if s.broken {
					t.Fatal(s)
				}
			}
		})
	}
}
EOF
  run
  expect_none
}

test_go_plain_table_driven_test_is_not_a_product() {
  setup
  write a_test.go <<'EOF'
package a

func TestParse(t *testing.T) {
	tests := []struct {
		name string
		in   string
	}{
		{name: "empty", in: ""},
		{name: "brace", in: "{"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			for _, r := range tt.in {
				_ = r
			}
		})
	}
}
EOF
  run
  expect_none
}

test_rust_two_values_lists() {
  setup
  write src/lib.rs <<'EOF'
#[cfg(test)]
mod tests {
    use rstest::rstest;

    #[rstest]
    fn conflict(
        #[values("normal", "visual")] mode: &str,
        #[values("h", "j")] key: &str,
    ) {
        assert!(check(mode, key));
    }
}
EOF
  run
  expect_found "$(printf 'src/lib.rs:5\trstest-values')"
}

test_rust_cases_combined_with_values() {
  setup
  write tests/a.rs <<'EOF'
#[rstest]
#[case(1, 2)]
#[case(2, 3)]
fn add(#[case] a: u32, #[case] b: u32, #[values("x", "y")] t: &str) {
    assert!(a < b && !t.is_empty());
}

#[apply(base)]
fn reuse(a: u32, #[values("x", "y")] t: &str) {
    assert!(a > 0 && !t.is_empty());
}
EOF
  run
  expect_found "$(printf 'tests/a.rs:1\trstest-values')" "$(printf 'tests/a.rs:8\trstest-values')"
}

test_rust_cases_only_is_not_a_product() {
  setup
  write tests/a.rs <<'EOF'
#[rstest]
#[case("{", 1)]
#[case("}", 2)]
fn parse(#[case] input: &str, #[case] want: usize) {
    assert_eq!(count(input), want);
}

#[rstest]
fn single(#[values("a", "b")] x: &str) {
    assert!(!x.is_empty());
}
EOF
  run
  expect_none
}

test_fails_when_base_is_unreadable() {
  setup
  B=no-such-commit
  run
  assert_eq 2 "$CODE"
}

test_fails_without_args() {
  setup
  ${SH:-sh} "$SCRIPT" "$R" >"$T/out" 2>"$T/err"
  assert_eq 2 "$?"
}

run_tests
