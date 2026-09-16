#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
quality_script="${script_dir}/check_transcript_quality.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/transcript-quality-test.XXXXXX")"

cleanup() {
  rm -rf "${test_dir}"
}

trap cleanup EXIT

write_transcript() {
  local output_path="$1"
  shift

  jq -n --args '$ARGS.positional | {segments: map({text: .})}' -- "$@" > "${output_path}"
}

assert_status() {
  local test_name="$1"
  local expected_status="$2"
  local transcript_path="$3"
  local actual_status

  set +e
  "${quality_script}" "${transcript_path}" >/dev/null 2>&1
  actual_status=$?
  set -e

  if [[ "${actual_status}" -ne "${expected_status}" ]]; then
    echo "FAIL: ${test_name}: expected status ${expected_status}, got ${actual_status}" >&2
    exit 1
  fi

  echo "PASS: ${test_name}"
}

write_transcript \
  "${test_dir}/healthy.json" \
  "料金プランを確認します" \
  "36時間を超える場合を確認します" \
  "次回までに資料を共有します"

repeated_segments=()
for _ in {1..25}; do
  repeated_segments+=("1時間延長に")
done
write_transcript "${test_dir}/degenerate.json" "${repeated_segments[@]}"

nineteen_repeated_segments=()
for _ in {1..19}; do
  nineteen_repeated_segments+=("同じ発言")
done
write_transcript "${test_dir}/nineteen-consecutive.json" "${nineteen_repeated_segments[@]}" "別の発言"

twenty_repeated_segments=()
for _ in {1..20}; do
  twenty_repeated_segments+=("同じ発言")
done
write_transcript "${test_dir}/twenty-consecutive.json" "${twenty_repeated_segments[@]}"

write_dominant_transcript() {
  local output_path="$1"
  local total="$2"
  local dominant_count="$3"
  local whitespace_variant="${4:-0}"
  local -a segments
  local index

  segments=()
  for ((index = 1; index <= total; index++)); do
    if [[ "${index}" -le $((dominant_count * 2)) && $((index % 2)) -eq 1 ]]; then
      if [[ "${whitespace_variant}" -eq 1 ]]; then
        case $((index % 6)) in
          1) segments+=("繰り返し発言") ;;
          3) segments+=("  繰り返し発言") ;;
          5) segments+=("繰り返し発言  ") ;;
        esac
      else
        segments+=("繰り返し発言")
      fi
    else
      segments+=("固有の発言${index}")
    fi
  done
  write_transcript "${output_path}" "${segments[@]}"
}

write_dominant_transcript "${test_dir}/ninety-nine-total.json" 99 20
write_dominant_transcript "${test_dir}/nineteen-percent-dominant.json" 100 19
write_dominant_transcript "${test_dir}/twenty-percent-dominant.json" 100 20
write_dominant_transcript "${test_dir}/whitespace-normalized.json" 100 20 1

assert_status \
  "内容が変化する文字起こしは正常と判定する" \
  0 \
  "${test_dir}/healthy.json"

assert_status \
  "同一文が20区間以上続く文字起こしは異常と判定する" \
  65 \
  "${test_dir}/degenerate.json"

assert_status \
  "同一文が19区間なら正常と判定する" \
  0 \
  "${test_dir}/nineteen-consecutive.json"

assert_status \
  "同一文が20区間なら異常と判定する" \
  65 \
  "${test_dir}/twenty-consecutive.json"

assert_status \
  "99区間なら同一文が20区間あっても占有率判定を適用しない" \
  0 \
  "${test_dir}/ninety-nine-total.json"

assert_status \
  "100区間中19区間が同一文なら正常と判定する" \
  0 \
  "${test_dir}/nineteen-percent-dominant.json"

assert_status \
  "100区間中20区間が同一文なら異常と判定する" \
  65 \
  "${test_dir}/twenty-percent-dominant.json"

assert_status \
  "前後空白を除くと100区間中20区間が同一文なら異常と判定する" \
  65 \
  "${test_dir}/whitespace-normalized.json"
