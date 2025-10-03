import { parseArgs } from "jsr:@std/cli/parse-args";
import $ from "jsr:@david/dax";

type Notification = {
  session_id: string;
  transcript_path: string;
  message: string;
  title: string;
};

const flags = parseArgs(Deno.args, {
  string: ["type"],
});

// When called from Notification hooks
async function notify() {
  const input: Notification = await new Response(Deno.stdin.readable).json();
  await $`terminal-notifier -title "${input.title}" -message "${input.message}" -sound default`;
}

// When called from Stop hooks
async function notifyWhenStop() {
  await $`terminal-notifier -title "Claude Code" -message "Wait next action" -sound default`;
}

async function main() {
  switch (flags.type) {
    case "notify":
      await notify();
      break;
    case "stop":
      await notifyWhenStop();
      break;
  }
}

if (Deno.build.os === "darwin") {
  await main();
}
