# launchd ジョブ

`utility-self-improving` スキルを **Mac Studio 限定で週次自動実行** するための launchd plist。

## 配置手順

```bash
# 1. ログディレクトリ作成
mkdir -p ~/.claude/logs

# 2. plist を LaunchAgents にコピー
cp ~/dev/github.com/skanehira/dotfiles/claude/launchd/com.skanehira.utility-self-improving.plist \
   ~/Library/LaunchAgents/

# 3. launchd に登録 (新形式)
launchctl bootstrap gui/$(id -u) \
  ~/Library/LaunchAgents/com.skanehira.utility-self-improving.plist

# 4. 登録確認 (PID 列が `-` なら待機中、数字なら実行中)
launchctl list | grep self-improving
```

## 動作テスト (即時実行)

```bash
launchctl kickstart gui/$(id -u)/com.skanehira.utility-self-improving
```

実行中の様子はログで確認:

```bash
# 進捗ログ (実行中もリアルタイムで主要マイルストーンが書かれる、見やすい)
tail -f ~/.claude/logs/self-improving-progress.log

# stdout (claude の最終応答テキストを markdown のまま記録。`.result` を抽出している)
tail -f ~/.claude/logs/self-improving.log

# stderr (エラー時のみ)
tail -f ~/.claude/logs/self-improving.err

# 全 JSON (デバッグ用、messages 配列も含む raw。普段は読まなくて良い)
less ~/.claude/logs/self-improving.json
```

`/utility-self-improving` が正常に走れば Draft PR が GitHub に立つはず (`gh pr list -R skanehira/dotfiles`)。

## スケジュール

- **毎週日曜 05:00** (`StartCalendarInterval`: Weekday=0, Hour=5, Minute=0)
- 1 週間分 (直近 7 日) の履歴を解析する想定 (SKILL.md のデフォルト引数と一致)
- 変更したい場合は plist の `StartCalendarInterval` を編集して再配置 (`bootout` → `cp` → `bootstrap`)

## 実行コマンドの内訳

```
claude -p "/utility-self-improving"
  --permission-mode acceptEdits         # ファイル編集と一部 Bash を自動許可
  --allowedTools "Bash,Read,Edit,Write,Glob,Grep,Agent"  # session 全体の許可リスト
  --output-format json                  # 機械可読な結果
```

skill frontmatter の `allowed-tools` (Read/Edit/Write/Glob/Bash/Agent) と CLI 側 `--allowedTools` の積集合が実際の許可ツール。CLI 側は `Grep` を余分に含めているが、skill 側で絞られるため問題なし。

## 停止・解除

```bash
launchctl bootout gui/$(id -u)/com.skanehira.utility-self-improving
rm ~/Library/LaunchAgents/com.skanehira.utility-self-improving.plist
```

## トラブルシュート

| 症状                       | 確認・対処                                                                                                                  |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| 起動しない                 | `launchctl print gui/$(id -u)/com.skanehira.utility-self-improving` で last exit code を見る                                |
| `claude` が見つからない    | `EnvironmentVariables.PATH` に `~/.local/bin` (claude のインストール先) が含まれているか確認。インストール先が異なる場合は PATH に追加。なお `bash` は **`-c` (非ログイン)** で起動している (`-lc` だと macOS の `/etc/profile` 経由で `path_helper` が PATH を再構築し、launchd の PATH を上書きする) |
| permission prompt で止まる | `--permission-mode acceptEdits` でカバーできないツールが必要なケース。stderr ログで該当ツール特定 → `--allowedTools` に追加 |
| dotfilesリポ dirty で中断  | スキル側の意図的な挙動 (前提チェック)。手動で対応してから次回を待つ                                                         |
| Draft PR が立たない        | gh CLI の認証期限切れの可能性。`gh auth status` を確認                                                                      |
