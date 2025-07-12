# Claude Code Hooks

This directory contains custom hooks for Claude Code to enhance the development workflow.

## Files

- `format.ts` - Automatically formats files after Claude Code writes or edits them
- `notify.ts` - Sends desktop notifications for Claude Code events
- `types.ts` - TypeScript type definitions for Claude Code hook data structures

## Type Definitions

The `types.ts` file provides TypeScript types for Claude Code tool parameters:

### PostToolUseHookData

```typescript
type PostToolUseHookData<T = ToolParams> = {
  session_id: string;
  transcript_path: string;
  hook_event_name: string;
  tool_name: string;
  tool_input: T;
  tool_response: {
    filePath?: string;
    success: boolean;
  };
};
```

### Tool Parameter Types

- **WriteToolParams**: Parameters for the Write tool
  - `file_path`: string - The absolute path to write to
  - `content`: string - The content to write

- **EditToolParams**: Parameters for the Edit tool
  - `file_path`: string - The absolute path to edit
  - `old_string`: string - The text to replace
  - `new_string`: string - The replacement text
  - `replace_all?`: boolean - Whether to replace all occurrences

- **MultiEditToolParams**: Parameters for the MultiEdit tool
  - `file_path`: string - The absolute path to edit
  - `edits`: Array of edit operations, each containing:
    - `old_string`: string
    - `new_string`: string
    - `replace_all?`: boolean

## Usage

The hooks are configured in `../settings.json` and are automatically executed by Claude Code when the specified events occur.

### Format Hook

The format hook runs after Write, Edit, or MultiEdit operations and automatically formats files based on their extension:

- `.go` files - formatted with `gofmt`
- `.rs` files - formatted with `rustfmt`
- `.ts`, `.tsx`, `.js`, `.jsx` files - formatted with Biome (for Node.js projects) or Deno
- `.json`, `.jsonc` files - formatted with `jq`

### Notify Hook

The notify hook sends desktop notifications when:
- Claude Code stops execution (`Stop` event)
- Claude Code needs user attention (`Notification` event)