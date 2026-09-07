#!/usr/bin/env bash

set -euo pipefail

# Exit codes follow BSD sysexits.h (64=usage, 65=data error, 66=no input,
# 69=service unavailable, 70=software error, 73=can't create output).
usage="Usage: transcribe.sh <input-audio> <output-directory> [language]"

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

for dependency in ffprobe uvx; do
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

for output_file in transcript.json transcript.txt transcript.vtt; do
  if [[ -e "${output_directory}/${output_file}" ]]; then
    echo "Error: output already exists: ${output_directory}/${output_file}" >&2
    exit 73
  fi
done

# large-v3-turbo balances Japanese recognition accuracy and local inference speed.
model="${MLX_WHISPER_MODEL:-mlx-community/whisper-large-v3-turbo}"

language_arguments=()
if [[ "${language}" != "auto" ]]; then
  language_arguments=(--language "${language}")
fi

uvx --from mlx-whisper mlx_whisper \
  "${input_audio}" \
  --model "${model}" \
  --task transcribe \
  --output-dir "${output_directory}" \
  --output-name transcript \
  --output-format all \
  --verbose False \
  "${language_arguments[@]}"

for output_file in transcript.json transcript.txt transcript.vtt; do
  if [[ ! -s "${output_directory}/${output_file}" ]]; then
    echo "Error: transcription output is missing or empty: ${output_directory}/${output_file}" >&2
    exit 70
  fi
done

echo "Transcription completed: ${output_directory}"
