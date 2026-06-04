// OpenCode plugin: Ghostty progress bar for Claude usage.
// Shows the 5h/7d rate-limit utilization as Ghostty's native progress bar.
//
// Blue (state 1) = 5h window is the limiter
// Yellow/paused (state 4) = 7d window is the limiter
// State 0 = clear (no data yet)

import { createWriteStream } from "node:fs";
import { open } from "node:fs/promises";

const PROXY_PORT = process.env.JAIL_PROXY_PORT || "18911";
const PROXY_BASE = process.env.OPENCODE_PROXY_URL
  ? process.env.OPENCODE_PROXY_URL.replace(/\/v1\/?$/, "")
  : `http://127.0.0.1:${PROXY_PORT}`;
const USAGE_URL = `${PROXY_BASE}/v1/usage`;
const POLL_INTERVAL_MS = 10_000; // 10s — well within Ghostty's 15s stale timeout

let ttyFd = null;
let ttyWriter = null;

async function openTty() {
  if (ttyWriter) return true;
  try {
    const handle = await open("/dev/tty", "w");
    ttyFd = handle;
    ttyWriter = createWriteStream(null, { fd: handle.fd, autoClose: false });
    return true;
  } catch {
    return false;
  }
}

function writeOsc(state, pct) {
  if (!ttyWriter) return;
  // OSC 9;4;<state>;<pct> ST
  const rounded = Math.max(0, Math.min(100, Math.round(pct)));
  ttyWriter.write(`\x1b]9;4;${state};${rounded}\x1b\\`);
}

function clearProgress() {
  if (!ttyWriter) return;
  ttyWriter.write(`\x1b]9;4;0\x1b\\`);
}

let lastState = null;
let lastPct = null;
let eventDebounce = null;

async function updateProgress() {
  try {
    const resp = await fetch(USAGE_URL, {
      signal: AbortSignal.timeout(3000),
    });
    if (!resp.ok) return;
    const data = await resp.json();

    const fiveH = data.five_hour_utilization ?? null;
    const sevenD = data.seven_day_utilization ?? null;

    if (fiveH === null && sevenD === null) return;

    const fivePct = fiveH !== null ? fiveH * 100 : 0;
    const sevenPct = sevenD !== null ? sevenD * 100 : 0;

    let state, pct;
    if (sevenPct > fivePct) {
      // 7d window is the limiter → yellow (paused state)
      state = 4;
      pct = sevenPct;
    } else {
      // 5h window is the limiter (or equal) → blue (in progress state)
      state = 1;
      pct = fivePct;
    }

    // Only write if changed (avoid unnecessary writes)
    if (state !== lastState || Math.round(pct) !== Math.round(lastPct ?? -1)) {
      writeOsc(state, pct);
      lastState = state;
      lastPct = pct;
    }
  } catch {
    // Proxy not available — no-op
  }
}

function debouncedUpdate() {
  if (eventDebounce) clearTimeout(eventDebounce);
  eventDebounce = setTimeout(updateProgress, 1000);
}

export default async (_ctx) => {
  const hasTty = await openTty();
  if (!hasTty) return {};

  // Initial fetch
  updateProgress();

  // Periodic polling — keeps the bar alive (Ghostty's 15s stale timeout)
  const timer = setInterval(updateProgress, POLL_INTERVAL_MS);

  return {
    // Refresh after each LLM step completes (proxy just got fresh headers)
    event: async ({ event }) => {
      if (
        event.type === "session.next.step.ended" ||
        event.type === "message.updated"
      ) {
        debouncedUpdate();
      }

      // Clear on session delete (cleanup)
      if (event.type === "session.deleted") {
        clearProgress();
      }
    },
  };
};
