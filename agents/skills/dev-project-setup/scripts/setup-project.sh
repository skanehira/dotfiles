#!/usr/bin/env bash
# GraphQL の変数 ($o や $id) はシェルに展開させず、そのまま API へ渡す
# shellcheck disable=SC2016
# usage: setup-project.sh <owner/repo> [--business] [--project <number>]
#
# リポジトリに紐づく非公開の Project を用意し、Status の列を定義どおりに揃える。
# 最後の行に「PROJECT <owner> <number> <url>」を出す。
set -euo pipefail

repo=${1:?usage: setup-project.sh <owner/repo> [--business] [--project <number>]}
shift
business=""
number=""
while [ $# -gt 0 ]; do
  case "$1" in
    --business) business=1 ;;
    --project) number=${2:?--project needs a number}; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
owner=${repo%%/*}
name=${repo#*/}

statuses=("未整理|GRAY|AI の整理待ち" "設計待ち|YELLOW|AI の設計待ち" "設計レビュー|BLUE|人の設計レビュー待ち"
  "着手可能|GREEN|人が承認した。AI が実装してよい" "作業中|ORANGE|AI が実装中" "判断待ち|RED|人か顧客の判断待ち"
  "完了|PURPLE|close 済み")
if [ -n "$business" ]; then statuses+=("事業・運営|PINK|開発の対象外"); fi

# 既存の Project を探す。番号の指定が無ければ、リポジトリに紐づく Project のうちタイトルがリポジトリ名と同じものを使う。
if [ -z "$number" ]; then
  number=$(gh api graphql -f query='query($o:String!,$n:String!){repository(owner:$o,name:$n){projectsV2(first:50){nodes{number title closed}}}}' \
    -F o="$owner" -F n="$name" --jq "[.data.repository.projectsV2.nodes[]|select(.closed|not)|select(.title==\"$name\")][0].number // empty")
fi
if [ -z "$number" ]; then
  number=$(gh project create --owner "$owner" --title "$name" --format json --jq .number)
  gh project link "$number" --owner "$owner" --repo "$repo" >/dev/null
  echo "created project #$number"
else
  echo "kept project #$number"
fi
gh project edit "$number" --owner "$owner" --visibility PRIVATE >/dev/null
project_id=$(gh project view "$number" --owner "$owner" --format json --jq .id)
url=$(gh project view "$number" --owner "$owner" --format json --jq .url)

# Status の列を揃える。既存の列は id を付けて送る。id を付けないと、その列にある item の Status が消える (2026-11-05 に実測)。
field=$(gh api graphql -f query='query($id:ID!){node(id:$id){... on ProjectV2{field(name:"Status"){... on ProjectV2SingleSelectField{id options{id name color description}}}}}}' -F id="$project_id")
field_id=$(jq -r .data.node.field.id <<<"$field")
current=$(jq -c '.data.node.field.options' <<<"$field")
used=$(gh project item-list "$number" --owner "$owner" --format json --limit 5000 --jq '[.items[].status|select(.!=null)]|unique')

wanted='[]'
for entry in "${statuses[@]}"; do
  IFS='|' read -r sname scolor sdesc <<<"$entry"
  wanted=$(jq -c --arg n "$sname" --arg c "$scolor" --arg d "$sdesc" --argjson cur "$current" \
    '. + [(($cur|map(select(.name==$n))[0]) // {name:$n,color:$c,description:$d}) | {id,name,color,description} | with_entries(select(.value!=null))]' <<<"$wanted")
done
# 定義に無い列は、item があれば残して報告し、無ければ消す。
extras=$(jq -c --argjson w "$wanted" --argjson used "$used" \
  '[.[]|select(.name as $n|($w|map(.name)|index($n))==null)|select(.name as $n|$used|index($n))|{id,name,color,description}]' <<<"$current")
dropped=$(jq -r --argjson w "$wanted" --argjson used "$used" \
  '[.[]|select(.name as $n|($w|map(.name)|index($n))==null)|select(.name as $n|($used|index($n))==null)|.name]|join(" ")' <<<"$current")
options=$(jq -c --argjson e "$extras" '. + $e' <<<"$wanted")

if [ "$(jq -c 'map(.name)' <<<"$options")" = "$(jq -c 'map(.name)' <<<"$current")" ]; then
  echo "kept status columns"
else
  gh api graphql --input - >/dev/null <<EOF
{"query":"mutation(\$f:ID!,\$o:[ProjectV2SingleSelectFieldOptionInput!]){updateProjectV2Field(input:{fieldId:\$f,singleSelectOptions:\$o}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}","variables":{"f":"$field_id","o":$options}}
EOF
  echo "updated status columns: $(jq -r 'map(.name)|join(" / ")' <<<"$options")"
  [ -z "$dropped" ] || echo "dropped empty columns: $dropped"
fi
[ "$(jq length <<<"$extras")" = 0 ] || echo "WARN columns outside the definition still have items: $(jq -r 'map(.name)|join(" ")' <<<"$extras")"

if [ -n "$business" ]; then
  if gh project field-list "$number" --owner "$owner" --format json --jq '.fields[].name' | grep -qxF "区分"; then
    echo "kept field 区分"
  else
    gh project field-create "$number" --owner "$owner" --name "区分" --data-type SINGLE_SELECT --single-select-options "開発,事業・運営" >/dev/null
    echo "created field 区分"
  fi
fi

gh variable set PROJECT_OWNER --repo "$repo" --body "$owner" >/dev/null
gh variable set PROJECT_NUMBER --repo "$repo" --body "$number" >/dev/null
echo "set repository variables PROJECT_OWNER / PROJECT_NUMBER"
echo "PROJECT $owner $number $url"
