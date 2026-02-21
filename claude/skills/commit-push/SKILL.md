---
name: commit-push
description: "変更内容を分析し、Conventional Commit形式でコミットしてpushする"
argument-hint: "[--no-push]"
---

# /commit-push

Task tool で `commit-pusher` サブエージェントを起動してコミット＆プッシュを実行。

- 引数なし → コミット後にプッシュ
- `--no-push` → コミットのみ

引数 `$ARGUMENTS` をそのまま commit-pusher に渡す。
