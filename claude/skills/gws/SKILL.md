---
name: gws
description: "Google Workspace (Docs/Drive/Gmail/Sheets/Slides) を gws CLI で操作する。docs.google.com・drive.google.com・mail.google.com の URL が貼られたとき、「ドキュメントに書いて」「スプレッドシートを読んで」「メールを送って」「Driveに保存して」「スライドを作って」「gws」などのリクエストで起動。"
---

# gws — Google Workspace CLI

> このスキルは手動管理。`gws generate-skills` を再実行すると旧分割スキル (gws-docs 等) が生成され本スキルと競合するので実行しない。

## サービス別ルーティング

依頼内容や URL から対象サービスを判定し、対応する reference ファイルを Read してから操作する。

| サービス | URL パターン                       | 参照                   |
| -------- | ---------------------------------- | ---------------------- |
| Docs     | `docs.google.com/document/...`     | `references/docs.md`   |
| Drive    | `drive.google.com/...`             | `references/drive.md`  |
| Gmail    | `mail.google.com/...`              | `references/gmail.md`  |
| Sheets   | `docs.google.com/spreadsheets/...` | `references/sheets.md` |
| Slides   | `docs.google.com/presentation/...` | `references/slides.md` |

## Installation

The `gws` binary must be on `$PATH`. See the project README for install options.

## Authentication

```bash
# Browser-based OAuth (interactive)
gws auth login

# Service Account
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
```

## Global Flags

| Flag                    | Description                                             |
| ----------------------- | ------------------------------------------------------- |
| `--format <FORMAT>`     | Output format: `json` (default), `table`, `yaml`, `csv` |
| `--dry-run`             | Validate locally without calling the API                |
| `--sanitize <TEMPLATE>` | Screen responses through Model Armor                    |

## CLI Syntax

```bash
gws <service> <resource> [sub-resource] <method> [flags]
```

### Method Flags

| Flag                        | Description                                   |
| --------------------------- | --------------------------------------------- |
| `--params '{"key": "val"}'` | URL/query parameters                          |
| `--json '{"key": "val"}'`   | Request body                                  |
| `-o, --output <PATH>`       | Save binary responses to file                 |
| `--upload <PATH>`           | Upload file content (multipart)               |
| `--page-all`                | Auto-paginate (NDJSON output)                 |
| `--page-limit <N>`          | Max pages when using --page-all (default: 10) |
| `--page-delay <MS>`         | Delay between pages in ms (default: 100)      |

## Security Rules

- **Never** output secrets (API keys, tokens) directly
- **Always** confirm with user before executing write/delete commands
- Prefer `--dry-run` for destructive operations
- Use `--sanitize` for PII/content safety screening

## Shell Tips

- **zsh `!` expansion:** Sheet ranges like `Sheet1!A1` contain `!` which zsh interprets as history expansion. Use double quotes with escaped inner quotes instead of single quotes:
  ```bash
  # WRONG (zsh will mangle the !)
  gws sheets +read --spreadsheet ID --range 'Sheet1!A1:D10'

  # CORRECT
  gws sheets +read --spreadsheet ID --range "Sheet1!A1:D10"
  ```
- **JSON with double quotes:** Wrap `--params` and `--json` values in single quotes so the shell does not interpret the inner double quotes:
  ```bash
  gws drive files list --params '{"pageSize": 5}'
  ```

## Discovering Commands

Before calling any API method, inspect it:

```bash
# Browse resources and methods
gws <service> --help

# Inspect a method's required params, types, and defaults
gws schema <service>.<resource>.<method>
```

Use `gws schema` output to build your `--params` and `--json` flags.
