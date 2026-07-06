# コミットルール

## コミット条件

以下のすべての条件が満たされた場合のみコミットする：

1. **すべてのテストが通過している** - 例外なし
2. **すべてのコンパイラ/リンター警告が解決されている**
3. **変更が単一の論理的な作業単位を表している**

## Conventional Commit 形式

subject は `<emoji> <type>: <subject>` 形式 (type: feat=✨ / fix=🐛 / docs=📝 / style=🎨 / refactor=♻️ / test=✅ / chore=🔧 / perf=⚡)。形式は `hooks/commit-msg-guard.ts` が PreToolUse で機械検証し、違反時は正しい形式を提示して deny する。

本文の末尾には以下を含める：

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

改行を含むメッセージは HEREDOC (`git commit -m "$(cat <<'EOF' ... EOF)"`) で渡す。

### 変更タイプのプレフィックス

Tidy First (rules/core/tdd.md) に基づき、subject に変更タイプを明示する：

- `[STRUCTURAL]`: 動作を変更しないコミット
- `[BEHAVIORAL]`: 動作を変更するコミット

## コミットの原則

- 大きく頻度の低いコミットより、小さく頻繁なコミットを使用
- 各コミットは機能を壊さずに元に戻せること
- 作業中のコードをコミットしない
- 関心事が複数混在する場合 (例: feat + docs + test) は、関心事ごとに個別にコミットする
