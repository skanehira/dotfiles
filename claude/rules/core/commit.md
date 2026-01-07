# コミットルール

## コミット条件

以下のすべての条件が満たされた場合のみコミットする：

1. **すべてのテストが通過している** - 例外なし
2. **すべてのコンパイラ/リンター警告が解決されている**
3. **変更が単一の論理的な作業単位を表している**

## Conventional Commit 形式

コミットメッセージは以下の形式に従う：

```
<emoji> <type>: <subject>

<body>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Type と Emoji

| Type | Emoji | 説明 |
|------|-------|------|
| feat | ✨ | 新機能追加 |
| fix | 🐛 | バグ修正 |
| docs | 📝 | ドキュメント更新 |
| style | 🎨 | フォーマット変更（動作に影響なし） |
| refactor | ♻️ | リファクタリング |
| test | ✅ | テスト追加・修正 |
| chore | 🔧 | ビルド・設定ファイル変更 |
| perf | ⚡ | パフォーマンス改善 |

### 変更タイプのプレフィックス

Tidy Firstアプローチに基づき、変更タイプを明示する（詳細は `rules/core/tdd.md` 参照）：

- `[STRUCTURAL]`: 動作を変更しないコミット
- `[BEHAVIORAL]`: 動作を変更するコミット

## コミットの原則

- 大きく頻度の低いコミットより、小さく頻繁なコミットを使用
- 各コミットは機能を壊さずに元に戻せること
- 作業中のコードをコミットしない
- コミットは単一の目的に集中させる
- 複数の関心事がある場合は、それぞれ個別にコミット

## 複数の関心事がある場合

異なる関心事が混在している場合は、関心事ごとにコミットを分割：

```
# 例：以下の関心事が混在
- 新機能追加（feat）
- ドキュメント更新（docs）
- テスト追加（test）

# 分割してコミット
1st: ✨ feat: add new feature
2nd: 📝 docs: update documentation
3rd: ✅ test: add unit tests
```

## HEREDOCによるコミット

改行を含むコミットメッセージはHEREDOCを使用：

```bash
git commit -m "$(cat <<'EOF'
✨ feat: add user authentication system

Implement JWT-based authentication with refresh tokens.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```
