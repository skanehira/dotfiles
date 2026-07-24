#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
transcribe_script="${script_dir}/transcribe.sh"
failures=0
invalid_audio="$(mktemp "${TMPDIR:-/tmp}/invalid-meeting-recording.XXXXXX.m4a")"
existing_output_dir="$(mktemp -d "${TMPDIR:-/tmp}/meeting-minutes-existing-output.XXXXXX")"
valid_audio="$(mktemp "${TMPDIR:-/tmp}/valid-meeting-recording.XXXXXX.m4a")"

cleanup() {
  rm -f "${invalid_audio}" "${valid_audio}"
  rm -rf "${existing_output_dir}"
}

trap cleanup EXIT

ffmpeg -v error -y -f lavfi -i anullsrc=r=8000:cl=mono -t 1 "${valid_audio}"

assert_failure() {
  local test_name="$1"
  local expected_status="$2"
  local expected_output="$3"
  shift 3

  local actual_output
  local actual_status

  set +e
  actual_output="$("${transcribe_script}" "$@" 2>&1)"
  actual_status=$?
  set -e

  if [[ "${actual_status}" -ne "${expected_status}" ]]; then
    echo "FAIL: ${test_name}: expected status ${expected_status}, got ${actual_status}" >&2
    failures=$((failures + 1))
    return
  fi

  if [[ "${actual_output}" != "${expected_output}" ]]; then
    echo "FAIL: ${test_name}: unexpected output" >&2
    echo "expected: ${expected_output}" >&2
    echo "actual:   ${actual_output}" >&2
    failures=$((failures + 1))
    return
  fi

  echo "PASS: ${test_name}"
}

assert_failure \
  "引数がない場合は使い方を表示する" \
  64 \
  "Usage: transcribe.sh <input-audio> <output-directory> [language]"

assert_failure \
  "入力音声が存在しない場合は拒否する" \
  66 \
  "Error: input audio does not exist: /tmp/nonexistent-meeting-recording.m4a" \
  "/tmp/nonexistent-meeting-recording.m4a" \
  "/tmp/transcribing-meeting-minutes-test-output"

assert_failure \
  "音声ストリームを読めない場合は拒否する" \
  65 \
  "Error: input does not contain a readable audio stream: ${invalid_audio}" \
  "${invalid_audio}" \
  "/tmp/transcribing-meeting-minutes-test-output"

touch "${existing_output_dir}/transcript.json"

assert_failure \
  "出力ディレクトリに既存の文字起こしがある場合は拒否する" \
  73 \
  "Error: output already exists: ${existing_output_dir}/transcript.json" \
  "${valid_audio}" \
  "${existing_output_dir}"

if [[ "${failures}" -ne 0 ]]; then
  exit 1
fi
