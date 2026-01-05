---
description: "変更内容を分析し、Conventional Commit形式でコミットしてpushする。コミットしたい、プッシュしたい、変更を保存したい時に使用。"
argument-hint: "[--no-push]"
---

# /commit-push - Git コミット & プッシュ

変更内容を分析し、Conventional Commit形式のコミットメッセージを作成してコミット・プッシュを実行します。

## 目次

1. [使い方](#使い方)
2. [変更内容の確認](#13-変更内容の確認)
3. [コミット実行](#23-コミット実行)
4. [プッシュ実行](#33-プッシュ実行)

---

## 使い方

```bash
/commit-push           # コミット＆プッシュ
/commit-push --no-push # コミットのみ
```

---

## [1/3] 変更内容の確認

### ステータス確認

```bash
git status
git diff --staged

# ステージされた変更がない場合
git add .
```

### 変更内容の分析

- 複数の異なる関心事がある場合は、それぞれの関心事ごとに個別にコミット
- 各関心事に適したファイルをステージング
- 適切なコミットメッセージを作成して即座にコミット

---

## [2/3] コミット実行

### コミットメッセージの形式

```
<emoji> <type>: <description>

<optional body>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Type と Emoji

| Type | Emoji | 説明 |
|------|-------|------|
| `feat` | ✨ | 新機能 |
| `fix` | 🐛 | バグ修正 |
| `docs` | 📝 | ドキュメント |
| `style` | 💄 | フォーマット |
| `refactor` | ♻️ | リファクタリング |
| `perf` | ⚡️ | パフォーマンス |
| `test` | ✅ | テスト |
| `chore` | 🔧 | ツール・設定 |
| `ci` | 🚀 | CI/CD |

状況に応じてより具体的なEmojiを選択（🚑️緊急修正、🔒️セキュリティ、🔥削除、✏️タイポ等）

### コミット実行

```bash
git add <files>

git commit -m "$(cat <<'EOF'
✨ feat: add user authentication system

Implement JWT-based authentication with refresh tokens.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### ガイドライン

- **現在形・命令形**: "add" (not "added")
- **簡潔な1行目**: 72文字以内
- **Why, not What**: 変更の理由を説明
- **アトミック**: 1つの論理的な変更

---

## [3/3] プッシュ実行

`$1`が`--no-push`の場合はスキップ。

### プッシュ

```bash
# アップストリーム確認
git rev-parse --abbrev-ref @{upstream} 2>/dev/null || echo "no upstream"

# プッシュ
git push
# または（アップストリーム未設定時）
git push -u origin $(git branch --show-current)
```

---

## 完了サマリー

```
✓ コミット & プッシュが完了しました

コミット:
- ✨ feat: add new feature
- 🐛 fix: resolve bug

プッシュ先:
- origin/<branch-name>
```

---

## 複数の関心事がある場合

自動的に関心事ごとにコミットを分割：

```
# 混在している変更
- 新機能追加（feat）
- ドキュメント更新（docs）

# 分割してコミット
1st: ✨ feat: add new feature
2nd: 📝 docs: update documentation

# 最後にまとめてプッシュ
git push
```

---

## 重要な注意事項

- **自動実行**: 変更内容を分析したら、即座にコミットを実行
- **関心事ごと**: 複数の関心事がある場合は、それぞれ個別にコミット
- **品質保証**: コミット前に必ず diff を確認
