#!/usr/bin/env bash
# Claude Code の statusLine コマンド。stdin の JSON (フィールドは 2026-08-22 に
# v2.1.238 の実出力をダンプして確認) を 1 行のステータスラインに整形する。
#
#   4m24s | $5.28 | ctx:11% | 5h:36% →8/22 18:00, 7d:51% →8/27 17:00 | Opus 5, high, think
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
  api_duration_ms cost_usd ctx_pct rate_5h reset_5h rate_7d reset_7d model_name effort thinking fast \
  < <(printf '%s' "$input" | jq -j '
        # resets_at は Unix epoch 秒。date の書式が BSD (-r) と GNU (-d @) で割れるため
        # jq 側でローカル時刻に整形して渡す。
        def reset_at: if . then strflocaltime("%-m/%-d %H:%M") else "" end;
        # used_percentage は 56.00000000000001 のような浮動小数点で来る。jq では 0 も
        # truthy なので、この形で 0% を落とさずに切り捨てられる。
        def pct: if . then floor else "" end;
        [ (.cost.total_api_duration_ms // ""),
          (.cost.total_cost_usd // ""),
          (.context_window.used_percentage | pct),
          (.rate_limits.five_hour.used_percentage | pct),
          (.rate_limits.five_hour.resets_at | reset_at),
          (.rate_limits.seven_day.used_percentage | pct),
          (.rate_limits.seven_day.resets_at | reset_at),
          (.model.display_name // .model.id // ""),
          (.effort.level // ""),
          (if .thinking.enabled == true then "1" else "" end),
          (if .fast_mode == true then "1" else "" end)
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
format_rate() {
  local label=$1 pct=$2 reset=$3
  [[ -z $pct ]] && return
  if [[ -n $reset ]]; then
    printf '%s:%s%% →%s' "$label" "$pct" "$reset"
  else
    printf '%s:%s%%' "$label" "$pct"
  fi
}
rate_group=$(join_comma "$(format_rate 5h "$rate_5h" "$reset_5h")" "$(format_rate 7d "$rate_7d" "$reset_7d")")
[[ -n $rate_group ]] && groups+=("$rate_group")

# 5. モデル / effort / thinking / fast mode
# display_name の "Opus 5 (1M context)" のような括弧付き注記は落として短縮する
model_short=${model_name%% (*}
thinking_label=""
[[ -n $thinking ]] && thinking_label="think"
fast_label=""
[[ -n $fast ]] && fast_label="fast"
model_group=$(join_comma "$model_short" "$effort" "$thinking_label" "$fast_label")
[[ -n $model_group ]] && groups+=("$model_group")

line=""
for group in "${groups[@]}"; do
  [[ -n $line ]] && line+=" | "
  line+="$group"
done
printf '%s\n' "$line"
