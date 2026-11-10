#!/usr/bin/env bash
# usage: setup-labels.sh <owner/repo> [--business]
#
# 状態のラベルは定義どおりに作るか上書きする。種別のラベルは無いときだけ作る。
# 種別のラベルを上書きしないのは、リポジトリが説明や色を独自に決めていることがあるため。
set -euo pipefail

repo=${1:?usage: setup-labels.sh <owner/repo> [--business]}
business=${2:-}

state_labels=(
  "needs-design|FBCA04|AI の設計待ち"
  "design-review|0052CC|人の設計レビュー待ち"
  "ready|0E8A16|人が仕様を承認した。AI が実装してよい"
  "in-progress|1D76DB|AI が実装中"
  "needs-human|D93F0B|人か顧客の判断待ち"
  "tracking|5319E7|親 issue。実装の対象ではない"
)
type_labels=(
  "bug|d73a4a|不具合"
  "enhancement|a2eeef|機能の追加・変更"
  "refactoring|c5def5|振る舞いを変えない改善"
  "question|d876e3|確認・質問"
)
if [ "$business" = "--business" ]; then
  type_labels+=("事業・運営|bfd4f2|開発の対象外の事業・運営の issue")
fi

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
