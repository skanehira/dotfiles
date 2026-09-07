---
name: workflow-commit
description: "変更内容を分析し、Conventional Commit形式でコミットする (pushはユーザが手動)"
model: haiku
---

# /workflow-commit

変更内容を分析し、関心事ごとに分割して Conventional Commit + Emoji 形式でコミットする。push はユーザが手動で行うため、このスキルは実行しない。

詳細なルールは @rules/core/commit.md を参照。

## 手順

### 1. 変更内容の確認

```bash
git status
git diff
git diff --staged
```

ステージされた変更がなければ作業ツリーから関心事を判定する。

### 2. 関心事ごとに分割

複数の異なる関心事 (feat / fix / docs / refactor / test / chore など) が混在している場合は、関心事ごとに別コミットに分割する。

判断軸：
- 動作変更の有無 (`[BEHAVIORAL]` / `[STRUCTURAL]`)
- 影響範囲 (機能 / ドキュメント / 設定 / テスト)
- 単一の論理単位として元に戻せるか

### 3. コミット実行

関心事ごとに以下を繰り返す：

```bash
git add <関心事のファイル>

git commit -m "$(cat <<'EOF'
✨ feat: add user authentication

Implement JWT-based authentication with refresh tokens.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

Conventional Commit type と emoji の対応表は @rules/core/commit.md を参照。

### 4. サマリ出力

```
✓ コミット完了

コミット:
- ✨ feat: add user authentication
- 📝 docs: update README

push はユーザが手動で実行してください。
```

## 注意

- コミット前に必ず `git diff --staged` で内容を確認する
- 各コミットが論理的にまとまっていて単独で revert 可能であること
- `git add -A` / `git add .` は不要なファイル混入リスクがあるので、関心事ごとにパスを明示する
- 動作変更コミットと構造変更コミットは混ぜない (Tidy First)
- push は実行しない (ユーザが手動で行う)
