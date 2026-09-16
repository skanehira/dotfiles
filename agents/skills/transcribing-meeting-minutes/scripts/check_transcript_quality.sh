#!/usr/bin/env bash

set -euo pipefail

usage="Usage: check_transcript_quality.sh <transcript.json>"

if [[ "$#" -ne 1 ]]; then
  echo "${usage}" >&2
  exit 64
fi

transcript_path="$1"

if [[ ! -s "${transcript_path}" ]]; then
  echo "Error: transcript does not exist or is empty: ${transcript_path}" >&2
  exit 66
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: required command is not installed: jq" >&2
  exit 69
fi

if ! metrics="$({
  jq -r '
    def normalized: gsub("^\\s+|\\s+$"; "");

    [.segments[]?.text // "" | normalized | select(length > 0)] as $texts
    | ($texts | length) as $total
    | if $total == 0 then
        [0, 0, 0]
      else
        (reduce $texts[] as $text (
          {previous: null, current: 0, max_run: 0};
          if .previous == $text then
            .current += 1
          else
            .previous = $text | .current = 1
          end
          | .max_run = ([.max_run, .current] | max)
        )) as $runs
        | ($texts | group_by(.) | map(length) | max) as $dominant_count
        | [$total, $runs.max_run, $dominant_count]
      end
    | @tsv
  ' "${transcript_path}"
} 2>/dev/null)"; then
  echo "Error: transcript JSON is invalid: ${transcript_path}" >&2
  exit 65
fi

IFS=$'\t' read -r total_segments max_run dominant_count <<< "${metrics}"

if [[ "${total_segments}" -eq 0 ]]; then
  echo "Error: transcript has no non-empty segments: ${transcript_path}" >&2
  exit 65
fi

dominant_percent=$((dominant_count * 100 / total_segments))

if [[ "${max_run}" -ge 20 ]] ||
  [[ "${total_segments}" -ge 100 && "${dominant_count}" -ge 20 && "${dominant_percent}" -ge 20 ]]; then
  echo "Degenerate transcript detected: segments=${total_segments} max_run=${max_run} dominant_count=${dominant_count} dominant_percent=${dominant_percent}%" >&2
  exit 65
fi

echo "Transcript quality check passed: segments=${total_segments} max_run=${max_run} dominant_count=${dominant_count} dominant_percent=${dominant_percent}%"
