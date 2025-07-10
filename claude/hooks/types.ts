// Type definitions for Claude Code PostToolUse hook

export type PostToolUseData<T = ToolParams> = {
  tool_name: string;
  tool_params: T;
  tool_result: string;
};

// Base tool parameter types
export type WriteToolParams = {
  file_path: string;
  content: string;
};

export type EditToolParams = {
  file_path: string;
  old_string: string;
  new_string: string;
  replace_all?: boolean;
};

export type MultiEditToolParams = {
  file_path: string;
  edits: Array<{
    old_string: string;
    new_string: string;
    replace_all?: boolean;
  }>;
};

// Union type for all file modification tools
export type FileModificationToolParams =
  | WriteToolParams
  | EditToolParams
  | MultiEditToolParams;

// Type guard functions
export function isWriteToolParams(params: unknown): params is WriteToolParams {
  return typeof params === "object" && params !== null &&
    "content" in params && "file_path" in params;
}

export function isEditToolParams(params: unknown): params is EditToolParams {
  return typeof params === "object" && params !== null &&
    "old_string" in params && "new_string" in params && "file_path" in params;
}

export function isMultiEditToolParams(
  params: unknown,
): params is MultiEditToolParams {
  return typeof params === "object" && params !== null &&
    "edits" in params &&
    Array.isArray((params as Record<string, unknown>).edits) &&
    "file_path" in params;
}

// Generic tool params type for other tools
export type ToolParams = FileModificationToolParams | Record<string, unknown>;
