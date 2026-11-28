#!/usr/bin/env bash
# usage: setup-labels.sh <owner/repo>
#
# dev-triage と dev-feat-spec が前提の確認で呼ぶ。何度実行しても結果は変わらない。
# 状態のラベルは定義どおりに作るか上書きする。種別のラベルは無いときだけ作る。
# 種別のラベルを上書きしないのは、リポジトリが説明や色を独自に決めていることがあるため。
# ready / in-progress / needs-human / tracking の色と説明は、dev-spec の references/issue-template.md
# 「ラベルの用意」と同じにする (どちらも --force で上書きするので、違うと実行のたびに書き換わる)。
set -euo pipefail

repo=${1:?usage: setup-labels.sh <owner/repo>}

state_labels=(
  "needs-design|FBCA04|AI の設計待ち"
  "design-review|0052CC|人の設計レビュー待ち"
  "ready|0E8A16|着手可能"
  "in-progress|1D76DB|dev-impl が実装中"
  "needs-human|D93F0B|人間の判断待ちで駐車中"
  "tracking|5319E7|親 issue (トラッキング)。実装対象ではない"
)
type_labels=(
  "bug|d73a4a|不具合"
  "enhancement|a2eeef|機能の追加・変更"
  "refactoring|c5def5|振る舞いを変えない改善"
  "question|d876e3|確認・質問"
)

existing=$(gh label list --repo "$repo" --limit 500 --json name --jq '.[].name')

for entry in "${state_labels[@]}"; do
  IFS='|' read -r name color desc <<<"$entry"
  if grep -qxF "$name" <<<"$existing"; then action=updated; else action=created; fi
  gh label create "$name" --repo "$repo" --force --color "$color" --description "$desc" >/dev/null
  echo "$action state $name"
done

for entry in "${type_labels[@]}"; do
  IFS='|' read -r name color desc <<<"$entry"
  if grep -qxF "$name" <<<"$existing"; then
    echo "kept type $name"
  else
    gh label create "$name" --repo "$repo" --color "$color" --description "$desc" >/dev/null
    echo "created type $name"
  fi
done
