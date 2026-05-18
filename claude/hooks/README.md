# Claude Code Hooks

Custom hooks for Claude Code.

## Files

- `notify.ts` — Sends desktop notifications for Claude Code events

## Usage

Hooks are configured in `../settings.json` and run automatically on the specified events.

### Notify Hook

Sends a desktop notification on:
- `Stop` event — Claude Code finishes a response
- `Notification` event — Claude Code needs user attention (e.g., permission prompt)

macOS only (uses `terminal-notifier`).
