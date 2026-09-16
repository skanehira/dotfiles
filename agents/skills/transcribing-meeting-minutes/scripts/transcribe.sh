#!/usr/bin/env bash

set -euo pipefail

# Exit codes follow BSD sysexits.h (64=usage, 65=data error, 66=no input,
# 69=service unavailable, 70=software error, 73=can't create output).
usage="Usage: transcribe.sh <input-audio> <output-directory> [language]"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
quality_script="${script_dir}/check_transcript_quality.sh"

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
  echo "${usage}" >&2
  exit 64
fi

input_audio="$1"
output_directory="$2"
language="${3:-ja}"

if [[ ! -f "${input_audio}" ]]; then
  echo "Error: input audio does not exist: ${input_audio}" >&2
  exit 66
fi

for dependency in ffprobe ffmpeg uvx jq; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    echo "Error: required command is not installed: ${dependency}" >&2
    exit 69
  fi
done

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "Error: mlx-whisper requires macOS on Apple Silicon" >&2
  exit 69
fi

if ! audio_stream_index="$(
  ffprobe \
    -v error \
    -select_streams a:0 \
    -show_entries stream=index \
    -of csv=p=0 \
    "${input_audio}" \
    2>/dev/null
)"; then
  echo "Error: input does not contain a readable audio stream: ${input_audio}" >&2
  exit 65
fi

if [[ -z "${audio_stream_index}" ]]; then
  echo "Error: input does not contain a readable audio stream: ${input_audio}" >&2
  exit 65
fi

mkdir -p "${output_directory}"

output_files=(transcript.json transcript.txt transcript.vtt transcript.srt transcript.tsv)

for output_file in "${output_files[@]}"; do
  if [[ -e "${output_directory}/${output_file}" ]]; then
    echo "Error: output already exists: ${output_directory}/${output_file}" >&2
    exit 73
  fi
done

if [[ -e "${output_directory}/first-pass" ]]; then
  echo "Error: output already exists: ${output_directory}/first-pass" >&2
  exit 73
fi

# large-v3-turbo balances Japanese recognition accuracy and local inference speed.
model="${MLX_WHISPER_MODEL:-mlx-community/whisper-large-v3-turbo}"

run_transcription() {
  local retry_mode="$1"
  local -a command

  command=(
    uvx --from mlx-whisper mlx_whisper
    "${input_audio}"
    --model "${model}"
    --task transcribe
    --output-dir "${output_directory}"
    --output-name transcript
    --output-format all
    --verbose False
  )

  if [[ "${language}" != "auto" ]]; then
    command+=(--language "${language}")
  fi

  if [[ "${retry_mode}" == "retry" ]]; then
    command+=(
      --condition-on-previous-text False
      --word-timestamps True
      --hallucination-silence-threshold 2
    )
  fi

  "${command[@]}"
}

assert_outputs_exist() {
  local output_file

  for output_file in "${output_files[@]}"; do
    if [[ ! -s "${output_directory}/${output_file}" ]]; then
      echo "Error: transcription output is missing or empty: ${output_directory}/${output_file}" >&2
      exit 70
    fi
  done
}

run_quality_check() {
  "${quality_script}" "${output_directory}/transcript.json"
}

run_transcription initial
assert_outputs_exist

set +e
quality_output="$(run_quality_check 2>&1)"
quality_status=$?
set -e
printf '%s\n' "${quality_output}" >&2

if [[ "${quality_status}" -eq 65 ]]; then
  mkdir "${output_directory}/first-pass"
  for output_file in "${output_files[@]}"; do
    if [[ -e "${output_directory}/${output_file}" ]]; then
      mv "${output_directory}/${output_file}" "${output_directory}/first-pass/${output_file}"
    fi
  done

  echo "Retrying transcription with repetition-resistant settings" >&2
  run_transcription retry
  assert_outputs_exist

  set +e
  quality_output="$(run_quality_check 2>&1)"
  quality_status=$?
  set -e
  printf '%s\n' "${quality_output}" >&2

  if [[ "${quality_status}" -ne 0 ]]; then
    echo "Error: retry transcription still failed the quality check" >&2
    exit 70
  fi
elif [[ "${quality_status}" -ne 0 ]]; then
  exit "${quality_status}"
fi

echo "Transcription completed: ${output_directory}"
