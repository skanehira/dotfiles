#!/usr/bin/env bash
# Claude Code の statusLine コマンド。stdin の JSON (フィールドは 2026-08-22 に
# v2.1.238 の実出力をダンプして確認) を 1 行のステータスラインに整形する。
#
#   4m24s | $5.28 | ctx:11% | 5h:36% 7d:51% | Opus 5, high, think | ~/dev/... (master) #4398e15b
#
# 欠落しうるフィールド (effort はモデル非対応時に不在、context_window の各値は
# セッション初期に null、rate_limits は Claude.ai サブスクリプション外では不在) が
# あるため、値が無い要素は出力から落とす。
set -uo pipefail

input=$(cat)

# statusLine はアシスタントメッセージごとに実行されるため jq の起動は 1 回に抑える。
# 区切りに \x1f (unit separator) を使うのは、IFS が空白文字だと空フィールドが
# 詰められて以降の代入位置がずれるため。
IFS=$'\x1f' read -r -d '' \
  api_duration_ms cost_usd ctx_pct rate_5h rate_7d model_name effort thinking fast cwd session_id \
  < <(printf '%s' "$input" | jq -j '
        [ (.cost.total_api_duration_ms // ""),
          (.cost.total_cost_usd // ""),
          (.context_window.used_percentage // ""),
          (.rate_limits.five_hour.used_percentage // ""),
          (.rate_limits.seven_day.used_percentage // ""),
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

# 1. 経過時間 (API 応答待ちの合計)
# total_duration_ms ではなく total_api_duration_ms を使う。前者は壁時計時間で、
# セッションを再開して使い続けると 272h のような値になり指標として読めないため。
if [[ $api_duration_ms =~ ^[0-9]+$ ]]; then
  groups+=("$(format_duration "$api_duration_ms")")
fi

# 2. 概算料金
if [[ -n $cost_usd ]]; then
  groups+=("$(awk -v c="$cost_usd" 'BEGIN { if (c + 0 < 0.01) print "<$0.01"; else printf "$%.2f", c }')")
fi

# 3. コンテキスト使用率
[[ -n $ctx_pct ]] && groups+=("ctx:${ctx_pct}%")

# 4. レートリミット使用率
# rate_limits は Claude.ai サブスクリプションのセッションにしか渡らず、渡る場合も
# 最初の API 応答までは不在なので、片方だけ来ても表示できるようにしておく。
rate_parts=()
[[ -n $rate_5h ]] && rate_parts+=("5h:${rate_5h}%")
[[ -n $rate_7d ]] && rate_parts+=("7d:${rate_7d}%")
((${#rate_parts[@]} > 0)) && groups+=("${rate_parts[*]}")

# 5. モデル / effort / thinking / fast mode
# display_name の "Opus 5 (1M context)" のような括弧付き注記は落として短縮する
model_short=${model_name%% (*}
thinking_label=""
[[ -n $thinking ]] && thinking_label="think"
fast_label=""
[[ -n $fast ]] && fast_label="fast"
model_group=$(join_comma "$model_short" "$effort" "$thinking_label" "$fast_label")
[[ -n $model_group ]] && groups+=("$model_group")

# 6. カレントディレクトリ / git ブランチ / セッション ID
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
