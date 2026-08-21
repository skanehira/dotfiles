#!/usr/bin/env bash
# Claude Code の statusLine コマンド。stdin の JSON (フィールドは 2026-08-22 に
# v2.1.238 の実出力をダンプして確認) を 1 行のステータスラインに整形する。
#
#   4m39s | in:112.9k out:3.0k $5.28 | ctx:11% | Opus 5, high, think | ~/dev/... (master) #4398e15b
#
# 欠落しうるフィールド (effort はモデル非対応時に不在、context_window の各値は
# セッション初期に null) があるため、値が無い要素は出力から落とす。
set -uo pipefail

input=$(cat)

# statusLine はアシスタントメッセージごとに実行されるため jq の起動は 1 回に抑える。
# 区切りに \x1f (unit separator) を使うのは、IFS が空白文字だと空フィールドが
# 詰められて以降の代入位置がずれるため。
IFS=$'\x1f' read -r -d '' \
  duration_ms cost_usd in_tokens out_tokens ctx_pct model_name effort thinking fast cwd session_id \
  < <(printf '%s' "$input" | jq -j '
        [ (.cost.total_duration_ms // ""),
          (.cost.total_cost_usd // ""),
          (.context_window.total_input_tokens // ""),
          (.context_window.total_output_tokens // ""),
          (.context_window.used_percentage // ""),
          (.model.display_name // .model.id // ""),
          (.effort.level // ""),
          (if .thinking.enabled == true then "1" else "" end),
          (if .fast_mode == true then "1" else "" end),
          (.workspace.current_dir // .cwd // ""),
          (.session_id // "")
        ] | map(tostring) | join("\u001f")
      '; printf '\0')

format_duration() {
  local ms=$1 total_sec h m s
  total_sec=$((ms / 1000))
  h=$((total_sec / 3600))
  m=$(((total_sec % 3600) / 60))
  s=$((total_sec % 60))
  if ((h > 0)); then
    printf '%dh%02dm' "$h" "$m"
  elif ((m > 0)); then
    printf '%dm%02ds' "$m" "$s"
  else
    printf '%ds' "$s"
  fi
}

format_tokens() {
  local n=$1
  if ((n < 1000)); then
    printf '%d' "$n"
  elif ((n < 1000000)); then
    printf '%d.%dk' "$((n / 1000))" "$(((n % 1000) / 100))"
  else
    printf '%d.%dM' "$((n / 1000000))" "$(((n % 1000000) / 100000))"
  fi
}

# ", " 区切りのグループを組み立てる (空要素は落とす)
join_comma() {
  local out="" part
  for part in "$@"; do
    [[ -z $part ]] && continue
    [[ -n $out ]] && out+=", "
    out+="$part"
  done
  printf '%s' "$out"
}

groups=()

# 1. 経過時間
if [[ $duration_ms =~ ^[0-9]+$ ]]; then
  groups+=("$(format_duration "$duration_ms")")
fi

# 2. トークン in/out と概算料金
usage_parts=()
[[ $in_tokens =~ ^[0-9]+$ ]] && usage_parts+=("in:$(format_tokens "$in_tokens")")
[[ $out_tokens =~ ^[0-9]+$ ]] && usage_parts+=("out:$(format_tokens "$out_tokens")")
if [[ -n $cost_usd ]]; then
  usage_parts+=("$(awk -v c="$cost_usd" 'BEGIN { if (c + 0 < 0.01) print "<$0.01"; else printf "$%.2f", c }')")
fi
((${#usage_parts[@]} > 0)) && groups+=("${usage_parts[*]}")

# 3. コンテキスト使用率
[[ -n $ctx_pct ]] && groups+=("ctx:${ctx_pct}%")

# 4. モデル / effort / thinking / fast mode
# display_name の "Opus 5 (1M context)" のような括弧付き注記は落として短縮する
model_short=${model_name%% (*}
thinking_label=""
[[ -n $thinking ]] && thinking_label="think"
fast_label=""
[[ -n $fast ]] && fast_label="fast"
model_group=$(join_comma "$model_short" "$effort" "$thinking_label" "$fast_label")
[[ -n $model_group ]] && groups+=("$model_group")

# 5. カレントディレクトリ / git ブランチ / セッション ID
location_parts=()
if [[ -n $cwd ]]; then
  location_parts+=("${cwd/#$HOME/\~}")
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  [[ -n $branch ]] && location_parts+=("($branch)")
fi
[[ -n $session_id ]] && location_parts+=("#${session_id:0:8}")
((${#location_parts[@]} > 0)) && groups+=("${location_parts[*]}")

line=""
for group in "${groups[@]}"; do
  [[ -n $line ]] && line+=" | "
  line+="$group"
done
printf '%s\n' "$line"
