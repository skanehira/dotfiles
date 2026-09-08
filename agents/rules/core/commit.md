# コミットルール

## コミット条件

以下のすべての条件が満たされた場合のみコミットする：

1. **すべてのテストが通過している** - 例外なし
2. **すべてのコンパイラ/リンター警告が解決されている**
3. **変更が単一の論理的な作業単位を表している**
4. **subject が下記の形式に一致している** - 機械ゲートは無いので自分で照合する

## Conventional Commit 形式

subject は `<emoji> <type>: <subject>` 形式 (type: feat=✨ / fix=🐛 / docs=📝 / style=🎨 / refactor=♻️ / test=✅ / chore=🔧 / perf=⚡)。形式を検証する機械ゲートは無い。**コミット後に `git log -1 --pretty=%s` を出力し、上の型と突き合わせる** (起草者と照合者が同一になるため、照合したことを出力に残して事後に検証できる状態にする)。

本文の末尾には以下を含める：

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

改行を含むメッセージは HEREDOC (`git commit -m "$(cat <<'EOF' ... EOF)"`) で渡す。

### 変更タイプのプレフィックス

Tidy First ({{@rules-root}}/core/tdd.md) に基づき、subject に変更タイプを明示する：

- `[STRUCTURAL]`: 動作を変更しないコミット
- `[BEHAVIORAL]`: 動作を変更するコミット

## コミットの原則

- 大きく頻度の低いコミットより、小さく頻繁なコミットを使用
- 各コミットは機能を壊さずに元に戻せること
- 作業中のコードをコミットしない
- 関心事が複数混在する場合 (例: feat + docs + test) は、関心事ごとに個別にコミットする
- 形式違反に気付いたら、push 前なら `git commit --amend` で直す。push 済みのものは書き換えず、次のコミットから守る
