#!/bin/sh
# sketch-shots.sh のテスト。Node.js と、キャッシュ済みの Playwright が無い環境では何もせずに通す
# (初回のインストールにはネットワークが要り、テストの中では入れない)。
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../sketch-shots.sh"
# shellcheck source=assert.sh
. "$HERE/assert.sh"

if ! command -v node >/dev/null 2>&1 || [ ! -f "${XDG_CACHE_HOME:-$HOME/.cache}/dev-feat-spec/playwright/node_modules/playwright/package.json" ]; then
  echo "skip: node か Playwright のキャッシュが無い"
  exit 0
fi

# 口のあるスケッチを書く。使い方: sketch <SKETCH_SCREENS の中身 (JS の配列)>
sketch() {
  cat >"$T/UI_SKETCH.html" <<HTML
<!DOCTYPE html><html><body><div id="root"></div><script>
const VIEWS = { home: "Home", list: "List", boom: "Boom" };
window.SKETCH_SCREENS = $1;
const id = new URLSearchParams(location.hash.slice(1)).get("screen") || "home";
const shown = VIEWS[id] ? id : "home";
document.getElementById("root").innerHTML = '<div data-sketch-screen="' + shown + '">' + VIEWS[shown] + "</div>";
if (shown === "boom") throw new Error("boom");
</script></body></html>
HTML
}

run() {
  ${SH:-sh} "$SCRIPT" "$T/UI_SKETCH.html" "$T/shots" >"$T/out.txt" 2>"$T/err.txt"
  echo $? >"$T/rc.txt"
}

test_captures_every_listed_screen() {
  sketch '["home", { id: "list", width: 390 }]'
  run
  assert_eq 0 "$(cat "$T/rc.txt")"
  assert_file_contains_line "$T/out.txt" "captured 2 / 2 (light)"
  assert_eq "light-home.png light-list.png" "$(cd "$T/shots" && echo *.png)"
}

# 一覧にあるのに描けない画面は、既定の画面を撮って成功にしない
test_fails_on_a_listed_screen_that_is_not_drawn() {
  sketch '["home", "ghost"]'
  run
  assert_eq 1 "$(cat "$T/rc.txt")"
  assert_eq 1 "$(grep -c '^FAIL ghost: ' "$T/err.txt")"
  assert_file_contains_line "$T/out.txt" "captured 1 / 2 (light)"
}

test_fails_on_a_page_error() {
  sketch '["home", "boom"]'
  run
  assert_eq 1 "$(cat "$T/rc.txt")"
  assert_eq 1 "$(grep -c '^FAIL boom: page error: ' "$T/err.txt")"
}

test_fails_without_the_screen_list() {
  sketch 'undefined'
  run
  assert_eq 1 "$(cat "$T/rc.txt")"
  assert_eq 1 "$(grep -c 'SKETCH_SCREENS' "$T/err.txt")"
}

run_tests
