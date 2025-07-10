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

// Function to send OSC notification (works with some terminal emulators)
function sendOSCNotification(title: string, message: string) {
  // OSC 777 is supported by some terminals like iTerm2, WezTerm
  const notification = `\x1b]777;notify;${title};${message}\x07`;
  console.log(notification);

  // Also try OSC 9 (older format)
  const osc9 = `\x1b]9;${title}: ${message}\x07`;
  console.log(osc9);

  // Terminal bell as fallback
  console.log("\x07");
}

// When called from Notification hooks
async function notify() {
  const input: Notification = await new Response(Deno.stdin.readable).json();

  if (isSSHSession()) {
    // Use OSC escape sequences for SSH sessions
    sendOSCNotification(input.title, input.message);
  } else {
    // Use terminal-notifier for local sessions
    await $`terminal-notifier -title "${input.title}" -message "${input.message}" -sound default`;
  }
}

// When called from Stop hooks
async function notifyWhenStop() {
  if (isSSHSession()) {
    console.log("Running in SSH session, using OSC notifications");
    // Use OSC escape sequences for SSH sessions
    sendOSCNotification("Claude Code", "Wait next action");
  } else {
    // Use terminal-notifier for local sessions
    await $`terminal-notifier -title "Claude Code" -message "Task was completed" -sound default`;
  }
}

switch (flags.type) {
  case "notify":
    await notify();
    break;
  case "stop":
    await notifyWhenStop();
    break;
}
