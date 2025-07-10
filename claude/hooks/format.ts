import $ from "jsr:@david/dax";
import { extname } from "jsr:@std/path";
import type { PostToolUseData, FileModificationToolParams } from "./types.ts";

async function getPostToolUseData(): Promise<PostToolUseData<FileModificationToolParams>> {
  return await new Response(Deno.stdin.readable).json();
}

async function formatFile(filePath: string) {
  const ext = extname(filePath);

  try {
    switch (ext) {
      case ".go":
        await $`gofmt -w ${filePath}`;
        console.log(`Formatted Go file: ${filePath}`);
        break;

      case ".rs":
        // Use rustfmt if available
        await $`rustfmt ${filePath}`;
        console.log(`Formatted Rust file: ${filePath}`);
        break;

      case ".ts":
      case ".tsx":
      case ".js":
      case ".jsx": {
        // Check if node_modules exists (Node.js project)
        const nodeModulesExists = await $.path("node_modules").exists();

        if (nodeModulesExists) {
          // Use biome for Node.js projects
          try {
            await $`npx @biomejs/biome format --write ${filePath}`;
            console.log(
              `Formatted TypeScript/JavaScript file with Biome: ${filePath}`,
            );
          } catch {
            console.log(`No formatter available for: ${filePath}`);
          }
        } else {
          // Use deno fmt as default
          await $`deno fmt ${filePath}`;
          console.log(
            `Formatted TypeScript/JavaScript file with Deno: ${filePath}`,
          );
        }
        break;
      }

      case ".json":
      case ".jsonc": {
        // Use jq to format JSON files
        try {
          await $`jq . ${filePath} > ${filePath}.tmp && mv ${filePath}.tmp ${filePath}`;
          console.log(`Formatted JSON file with jq: ${filePath}`);
        } catch {
          console.log(`Failed to format JSON file: ${filePath}`);
        }
        break;
      }

      default:
        console.log(`No formatter configured for extension: ${ext}`);
    }
  } catch (error) {
    console.error(`Error formatting ${filePath}:`, error);
  }
}

async function main() {
  const data = await getPostToolUseData();

  // Handle different tool types
  switch (data.tool_name) {
    case "Write":
    case "Edit":
    case "MultiEdit": {
      const filePath = data.tool_params.file_path;
      if (filePath) {
        await formatFile(filePath);
      }
      break;
    }

    default:
      // Ignore other tools
      break;
  }
}

await main();
