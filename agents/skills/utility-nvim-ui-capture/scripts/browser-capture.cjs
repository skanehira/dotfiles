#!/usr/bin/env node
// Opens the rtty page in Chromium, optionally sends keys, and screenshots the
// browser page (the terminal). The xterm.js DOM renderer is forced because the
// canvas renderer leaves horizontal seams in the screenshot.
//
// rtty starts the child process when the websocket opens, using the terminal
// size that FitAddon computed at load time. After the page loads we wait for
// fonts, re-fit the terminal (onResize sends the corrected size to the PTY),
// and scroll to the bottom so the screenshot shows the current screen instead
// of scrollback.
const { chromium } = require("playwright");

function arg(name, fallback) {
  const index = process.argv.indexOf("--" + name);
  return index === -1 ? fallback : process.argv[index + 1];
}

const url = arg("url");
const out = arg("out");
const width = Number(arg("width", "1280"));
const height = Number(arg("height", "800"));
const waitSeconds = Number(arg("wait", "2.5"));
const afterKeysSeconds = Number(arg("after-keys", "0.5"));
const keys = (arg("keys", "") || "")
  .split(";")
  .map((key) => key.trim())
  .filter(Boolean);
const headless = process.argv.includes("--headless");

if (!url || !out) {
  console.error("usage: browser-capture.cjs --url URL --out PATH [--width N] [--height N] [--wait S] [--keys KEYS] [--after-keys S] [--headless]");
  process.exit(2);
}

async function settle(page) {
  await page.evaluate(() => (document.fonts ? document.fonts.ready : Promise.resolve()));
  await page.waitForTimeout(200);
  await page.evaluate(() => {
    if (window.__captureFit) {
      window.__captureFit.fit();
    }
  });
  await page.waitForTimeout(1000);
  await page.evaluate(() => {
    const terminal = window.__captureTerminal;
    if (!terminal) {
      return;
    }
    if (typeof terminal.refresh === "function") {
      terminal.refresh(0, terminal.rows - 1);
    }
    if (typeof terminal.scrollToBottom === "function") {
      terminal.scrollToBottom();
    }
  });
}

(async () => {
  let browser;
  try {
    browser = await chromium.launch({ headless });
    const page = await browser.newPage({ viewport: { width, height } });

    await page.addInitScript(() => {
      let terminal;
      Object.defineProperty(window, "Terminal", {
        configurable: true,
        get() {
          return terminal;
        },
        set(original) {
          terminal = function (...args) {
            if (args[0] && typeof args[0] === "object") {
              args[0].rendererType = "dom";
            }
            const instance = new original(...args);
            window.__captureTerminal = instance;
            return instance;
          };
          terminal.prototype = original.prototype;
        },
      });

      let fitAddon;
      Object.defineProperty(window, "FitAddon", {
        configurable: true,
        get() {
          return fitAddon;
        },
        set(original) {
          const Original = original.FitAddon;
          original.FitAddon = function (...args) {
            const instance = new Original(...args);
            window.__captureFit = instance;
            return instance;
          };
          original.FitAddon.prototype = Original.prototype;
          fitAddon = original;
        },
      });
    });

    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 15000 });
    await page.waitForSelector("#terminal .xterm-screen", { timeout: 15000 });
    await settle(page);
    await page.waitForTimeout(waitSeconds * 1000);

    if (keys.length > 0) {
      await page.click("#terminal");
      for (const key of keys) {
        if (key.startsWith("text:")) {
          await page.keyboard.type(key.slice(5));
        } else {
          await page.keyboard.press(key);
        }
      }
      await page.waitForTimeout(afterKeysSeconds * 1000);
      await settle(page);
    }

    await page.screenshot({ path: out });
  } finally {
    if (browser) {
      await browser.close();
    }
  }
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
