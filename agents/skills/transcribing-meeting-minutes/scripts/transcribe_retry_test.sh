#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
transcribe_script="${script_dir}/transcribe.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/transcribe-retry-test.XXXXXX")"
fake_bin="${test_dir}/bin"
output_dir="${test_dir}/output"
audio_path="${test_dir}/recording.m4a"
state_dir="${test_dir}/state"

cleanup() {
  rm -rf "${test_dir}"
}

trap cleanup EXIT

mkdir -p "${fake_bin}" "${state_dir}"
touch "${audio_path}"

cat > "${fake_bin}/ffprobe" <<'EOF'
#!/usr/bin/env bash
echo 0
EOF

cat > "${fake_bin}/uvx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

count_file="${FAKE_UVX_STATE_DIR}/count"
log_file="${FAKE_UVX_STATE_DIR}/arguments"
count=0
if [[ -f "${count_file}" ]]; then
  count="$(<"${count_file}")"
fi
count=$((count + 1))
printf '%s\n' "${count}" > "${count_file}"
printf '%s\n' "$*" >> "${log_file}"

output_dir=""
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == "--output-dir" ]]; then
    output_dir="$2"
    shift 2
    continue
  fi
  shift
done

mkdir -p "${output_dir}"
if [[ "${FAKE_UVX_ALWAYS_DEGENERATE:-0}" == "1" || ( "${count}" -eq 1 && "${FAKE_UVX_FIRST_PASS:-degenerate}" == "degenerate" ) ]]; then
  jq -n '{segments: [range(0; 25) | {text: "1時間延長に"}]}' > "${output_dir}/transcript.json"
else
  jq -n '{segments: [{text: "料金プランを確認します"}, {text: "次回までに資料を共有します"}]}' > "${output_dir}/transcript.json"
fi
for extension in txt vtt srt tsv; do
  printf '%s transcript %s\n' "${extension}" "${count}" > "${output_dir}/transcript.${extension}"
done
EOF

chmod +x "${fake_bin}/ffprobe" "${fake_bin}/uvx"

PATH="${fake_bin}:${PATH}" \
  FAKE_UVX_STATE_DIR="${state_dir}" \
  /bin/bash "${transcribe_script}" "${audio_path}" "${output_dir}" ja >/dev/null

if [[ "$(<"${state_dir}/count")" != "2" ]]; then
  echo "FAIL: 反復崩れ検出後に1回だけ再実行する" >&2
  exit 1
fi

for extension in txt vtt srt tsv; do
  if [[ "$(<"${output_dir}/first-pass/transcript.${extension}")" != "${extension} transcript 1" ]]; then
    echo "FAIL: 初回${extension}をfirst-passへ内容を保って退避する" >&2
    exit 1
  fi
  if [[ "$(<"${output_dir}/transcript.${extension}")" != "${extension} transcript 2" ]]; then
    echo "FAIL: 再実行後の${extension}を正本として残す" >&2
    exit 1
  fi
done

expected_first_json="$(jq -nSc '{segments: [range(0; 25) | {text: "1時間延長に"}]}')"
actual_first_json="$(jq -Sc . "${output_dir}/first-pass/transcript.json")"
if [[ "${actual_first_json}" != "${expected_first_json}" ]]; then
  echo "FAIL: 初回JSONをfirst-passへ内容を保って退避する" >&2
  exit 1
fi

expected_final_json="$(jq -nSc '{segments: [{text: "料金プランを確認します"}, {text: "次回までに資料を共有します"}]}')"
actual_final_json="$(jq -Sc . "${output_dir}/transcript.json")"
if [[ "${actual_final_json}" != "${expected_final_json}" ]]; then
  echo "FAIL: 再実行後のJSONを正本として残す" >&2
  exit 1
fi

expected_retry='--condition-on-previous-text False --word-timestamps True --hallucination-silence-threshold 2'
if ! tail -n 1 "${state_dir}/arguments" | rg -F -q -- "${expected_retry}"; then
  echo "FAIL: 再実行で反復抑制オプションを指定する" >&2
  exit 1
fi

"${script_dir}/check_transcript_quality.sh" "${output_dir}/transcript.json" >/dev/null

echo "PASS: 反復崩れを退避して抑制設定で再実行する"

rm -rf "${output_dir}"
rm -f "${state_dir}/count" "${state_dir}/arguments"

PATH="${fake_bin}:${PATH}" \
  FAKE_UVX_STATE_DIR="${state_dir}" \
  FAKE_UVX_FIRST_PASS=healthy \
  /bin/bash "${transcribe_script}" "${audio_path}" "${output_dir}" ja >/dev/null

if [[ "$(<"${state_dir}/count")" != "1" ]]; then
  echo "FAIL: 正常な初回文字起こしは再実行しない" >&2
  exit 1
fi

if [[ -e "${output_dir}/first-pass" ]]; then
  echo "FAIL: 正常な初回文字起こしは退避ディレクトリを作らない" >&2
  exit 1
fi

echo "PASS: 正常な初回文字起こしは1回で完了する"

rm -rf "${output_dir}"
rm -f "${state_dir}/count" "${state_dir}/arguments"

set +e
PATH="${fake_bin}:${PATH}" \
  FAKE_UVX_STATE_DIR="${state_dir}" \
  FAKE_UVX_ALWAYS_DEGENERATE=1 \
  /bin/bash "${transcribe_script}" "${audio_path}" "${output_dir}" ja >/dev/null 2>&1
status=$?
set -e

if [[ "${status}" -ne 70 ]]; then
  echo "FAIL: 再実行後も反復崩れなら終了コード70で停止する (actual=${status})" >&2
  exit 1
fi

if [[ "$(<"${state_dir}/count")" != "2" ]]; then
  echo "FAIL: 品質不良でも再実行は1回だけに制限する" >&2
  exit 1
fi

echo "PASS: 再実行後も反復崩れなら1回で停止する"
