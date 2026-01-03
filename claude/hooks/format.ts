import $ from "jsr:@david/dax";
import { extname } from "jsr:@std/path";
import type {
  FileModificationToolParams,
  PostToolUseHookData,
} from "./types.ts";

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
          // Check for biome config
          const biomeConfigExists = await $.path("biome.json").exists() ||
            await $.path("biome.jsonc").exists();

          // Check for oxfmt config
          const oxfmtConfigExists = await $.path("oxfmt.toml").exists();

          let formatted = false;

          // Use biome for formatting if config exists
          if (biomeConfigExists) {
            try {
              await $`npx @biomejs/biome format --write ${filePath}`;
              console.log(
                `Formatted TypeScript/JavaScript file with Biome: ${filePath}`,
              );
              formatted = true;
            } catch {
              // biome not available or failed
            }
          }

          // Use oxfmt for formatting if config exists
          if (oxfmtConfigExists) {
            try {
              await $`npx oxfmt ${filePath}`;
              console.log(
                `Formatted TypeScript/JavaScript file with oxfmt: ${filePath}`,
              );
              formatted = true;
            } catch {
              // oxfmt not available or failed
            }
          }

          if (!formatted) {
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
  try {
    const data: PostToolUseHookData<FileModificationToolParams> =
      await new Response(Deno.stdin.readable).json();

    // Handle different tool types
    switch (data.tool_name) {
      case "Write":
      case "Edit":
      case "MultiEdit": {
        // Check if tool_input exists
        if (!data.tool_input) {
          return;
        }

        const filePath = data.tool_input.file_path;
        if (filePath) {
          await formatFile(filePath);
        }
        break;
      }

      default:
        // Ignore other tools
        break;
    }
  } catch (error) {
    console.error("Error in main function:", error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    await $`echo ${`FATAL ERROR: ${errorMessage}`} >> /tmp/claude_hook_format.log`;
  }
}

await main();
