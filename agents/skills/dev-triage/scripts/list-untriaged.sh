#!/usr/bin/env bash
# usage: list-untriaged.sh <owner/repo> [--excluded]
#
# 「未整理の issue」の唯一の定義。dev-triage の手順 1 と agent-loop が同じこのスクリプトを呼ぶ。
# 条件: open の issue (PR を除く) で、作成者が OWNER / MEMBER / COLLABORATOR、状態のラベルも
# 事業・運営 も付いておらず、作られてから 600 秒を超えている。
#
# 既定の出力: 条件に当たる issue の番号を 1 行に 1 つ、番号の小さい順に出す (API の既定は新しい順)。
# --excluded: 状態のラベルが無いのに外した件数を "author=<件数> young=<件数>" の 1 行で出す。
set -euo pipefail

repo=${1:?usage: list-untriaged.sh <owner/repo> [--excluded]}
mode=${2:-}

# gh の --jq は --arg / --argjson を受け取らないので、取得だけを gh で行い、判定は jq に渡す
issues=$(gh api --paginate "repos/$repo/issues?state=open&per_page=100" --jq '.[]' | jq -s '.')

# shellcheck disable=SC2016 # jq の式なので $ を展開しない
defs='
  def unlabeled: map(select(.pull_request | not)
    | select([.labels[].name]
      | any(.[]; IN("needs-design","design-review","ready","in-progress","needs-human","tracking","事業・運営")) | not));
  def member: .author_association | IN("OWNER","MEMBER","COLLABORATOR");
  def old_enough: now - (.created_at | fromdateiso8601) > 600;'

case "$mode" in
"")
  jq -r "$defs"' unlabeled | map(select(member and old_enough) | .number) | sort | .[]' <<<"$issues"
  ;;
--excluded)
  jq -r "$defs"' unlabeled
    | "author=\(map(select(member | not)) | length) young=\(map(select(member and (old_enough | not))) | length)"' <<<"$issues"
  ;;
*)
  echo "unknown option: $mode" >&2
  exit 2
  ;;
esac
