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

// Check if running in SSH session
function isSSHSession(): boolean {
  return Deno.env.get("SSH_CLIENT") !== undefined ||
    Deno.env.get("SSH_TTY") !== undefined ||
    Deno.env.get("SSH_CONNECTION") !== undefined;
}

// Skip notifications if in SSH session
if (isSSHSession()) {
  console.log("Running in SSH session, skipping notification");
  Deno.exit(0);
}

// When called from Notification hooks
async function notify() {
  const input: Notification = await new Response(Deno.stdin.readable).json();
  await $`terminal-notifier -title "${input.title}" -message "${input.message}" -sound default`;
}

// When called from Stop hooks
async function notifyWhenStop() {
  await $`terminal-notifier -title "Claude Code" -message "Wait next action" -sound default`;
}

switch (flags.type) {
  case "notify":
    await notify();
    break;
  case "stop":
    await notifyWhenStop();
    break;
}
