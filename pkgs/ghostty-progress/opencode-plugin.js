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
  lastState = null;
  lastPct = null;
  if (!ttyWriter) return;
  ttyWriter.write(`\x1b]9;4;0\x1b\\`);
}

// Last known good value. The heartbeat re-emits this every poll so Ghostty's
// 15s stale timeout never clears the bar, even when usage is steady or the
// proxy is briefly unavailable.
let lastState = null;
let lastPct = null;
let eventDebounce = null;

// Re-assert the current value to the terminal. No change-gate: Ghostty removes
// the progress bar 15s after the last OSC 9;4, so we must keep emitting.
function emit() {
  if (lastState === null) return;
  writeOsc(lastState, lastPct);
}

async function updateProgress() {
  try {
    const resp = await fetch(USAGE_URL, {
      signal: AbortSignal.timeout(3000),
    });
    if (resp.ok) {
      const data = await resp.json();

      const fiveH = data.five_hour_utilization ?? null;
      const sevenD = data.seven_day_utilization ?? null;

      if (fiveH !== null || sevenD !== null) {
        const fivePct = fiveH !== null ? fiveH * 100 : 0;
        const sevenPct = sevenD !== null ? sevenD * 100 : 0;

        if (sevenPct > fivePct) {
          // 7d window is the limiter → yellow (paused state)
          lastState = 4;
          lastPct = sevenPct;
        } else {
          // 5h window is the limiter (or equal) → blue (in progress state)
          lastState = 1;
          lastPct = fivePct;
        }
      }
    }
  } catch {
    // Proxy not available — fall through and re-emit the last known value.
  }

  // Always re-assert (holds the last value through hiccups, keeps bar alive).
  emit();
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
