// OpenCode plugin for claude-mem worker.
// Sends observations and summaries to the claude-mem HTTP worker.
//
// Hook API: flat string keys, async (input, output) => void
// Event API: async ({ event }) => void, event.type discriminant

import { createRequire } from "node:module";
const require = createRequire(
  (process.env.HOME || "/root") + "/.config/opencode/package.json"
);
const { z } = require("zod");

function resolveWorkerPort() {
  const fromEnv = process.env.CLAUDE_MEM_WORKER_PORT;
  const parsed = fromEnv ? parseInt(fromEnv.trim(), 10) : NaN;
  if (Number.isInteger(parsed) && parsed >= 1 && parsed <= 65535) return parsed;
  const uid = typeof process.getuid === "function" ? process.getuid() : 77;
  return 37700 + (uid % 100);
}

const WORKER = `http://127.0.0.1:${resolveWorkerPort()}`;
// Let the worker's LLM decide what's important — only clip extremely large outputs
const MAX_LEN = 20_000;
const HEADERS = { "Content-Type": "application/json" };

function post(path, body) {
  fetch(`${WORKER}${path}`, {
    method: "POST",
    headers: HEADERS,
    body: JSON.stringify(body),
  }).catch(() => {});
}

async function getText(path) {
  try {
    const r = await fetch(`${WORKER}${path}`, { headers: HEADERS });
    return r.ok ? await r.text() : null;
  } catch {
    return null;
  }
}

const sessionMap = new Map();
function contentId(sessionID) {
  if (!sessionMap.has(sessionID)) {
    if (sessionMap.size >= 500) sessionMap.delete(sessionMap.keys().next().value);
    sessionMap.set(sessionID, `opencode-${sessionID}-${Date.now()}`);
  }
  return sessionMap.get(sessionID);
}

const inited = new Set();
function ensureInit(sessionID, project) {
  const id = contentId(sessionID);
  if (!inited.has(id)) {
    inited.add(id);
    post("/api/sessions/init", { contentSessionId: id, project, prompt: "" });
  }
  return id;
}

function clip(s) {
  return typeof s === "string" && s.length > MAX_LEN ? s.slice(0, MAX_LEN) : (s || "");
}

// Debounce assistant message events — only send after streaming settles
const msgTimers = new Map();
const MSG_DEBOUNCE_MS = 2000;

export const ClaudeMemPlugin = async (ctx) => {
  const project = ctx.project?.name || "opencode";
  const cwd = ctx.directory;

  return {
    // Record tool observations
    "tool.execute.after": async (input, output) => {
      try {
        const id = ensureInit(input.sessionID, project);
        post("/api/sessions/observations", {
          contentSessionId: id,
          tool_name: input.tool,
          tool_input: input.args || {},
          tool_response: clip(output.output),
          cwd,
        });
      } catch {}
    },

    // Inject memory context into compaction prompt
    "experimental.session.compacting": async (input, output) => {
      try {
        const id = contentId(input.sessionID);
        if (!id || !inited.has(id)) return;
        const text = await getText(
          `/api/observations?q=${encodeURIComponent(project)}&limit=5`
        );
        if (text) {
          try {
            const data = JSON.parse(text);
            const items = Array.isArray(data.items) ? data.items : [];
            if (items.length > 0) {
              const mem = items.map((it, i) =>
                `${i + 1}. ${it.title || it.subtitle || "Untitled"}`
              ).join("\n");
              output.context.push(`## Claude-mem observations\n${mem}`);
            }
          } catch {}
        }
      } catch {}
    },

    // Inject recent memory context into messages (survives compat-proxy system prompt replacement)
    "experimental.chat.messages.transform": async (_input, output) => {
      try {
        const text = await getText(
          `/api/observations?q=${encodeURIComponent(project)}&limit=5`
        );
        if (!text) return;
        const data = JSON.parse(text);
        const items = Array.isArray(data.items) ? data.items : [];
        if (items.length === 0) return;
        const mem = items.map((it, i) => {
          const title = it.title || it.subtitle || "Untitled";
          const narrative = it.narrative || "";
          const snippet = narrative.length > 150
            ? narrative.slice(0, 150) + "…"
            : narrative;
          return `${i + 1}. **${title}** — ${snippet}`;
        }).join("\n");
        // Prepend as a synthetic system-context message
        output.messages.unshift({
          info: { role: "user" },
          parts: [{
            type: "text",
            text: `<claude-mem>\nRecent observations from persistent memory:\n${mem}\n</claude-mem>`,
          }],
        });
      } catch {}
    },

    // Bus events
    event: async ({ event }) => {
      try {
        const sid = event.properties?.sessionID;
        if (!sid) return;

        switch (event.type) {
          case "session.created": {
            ensureInit(sid, project);
            break;
          }

          // Debounced assistant messages — only capture final content after streaming settles
          case "message.updated": {
            if (event.properties?.info?.role !== "assistant") break;
            const id = contentId(sid);
            if (!inited.has(id)) break;

            const timerKey = `${sid}:${event.properties?.messageID}`;
            if (msgTimers.has(timerKey)) clearTimeout(msgTimers.get(timerKey));
            msgTimers.set(timerKey, setTimeout(() => {
              msgTimers.delete(timerKey);
              const parts = event.properties?.info?.parts || [];
              const textParts = parts
                .filter(p => p.type === "text")
                .map(p => p.text || p.content || "")
                .join("\n");
              if (!textParts) return;
              post("/api/sessions/observations", {
                contentSessionId: id,
                tool_name: "assistant_message",
                tool_input: {},
                tool_response: clip(textParts),
                cwd,
              });
            }, MSG_DEBOUNCE_MS));
            break;
          }

          // File edits — correct property name is "file", not "path"
          case "file.edited": {
            const id = contentId(sid);
            if (!inited.has(id)) break;
            const filePath = event.properties?.file || event.properties?.path || "unknown";
            post("/api/sessions/observations", {
              contentSessionId: id,
              tool_name: "file_edit",
              tool_input: { path: filePath },
              tool_response: `File edited: ${filePath}`,
              cwd,
            });
            break;
          }

          // Compaction completed — capture the distilled session summary
          case "session.next.compaction.ended": {
            const id = contentId(sid);
            if (!inited.has(id)) break;
            const summary = event.properties?.text || "";
            if (!summary) break;
            post("/api/sessions/observations", {
              contentSessionId: id,
              tool_name: "session_compaction_summary",
              tool_input: { reason: "compaction" },
              tool_response: clip(summary),
              cwd,
            });
            break;
          }

          // LLM step completed — capture work unit with cost/token metadata
          case "session.next.step.ended": {
            const id = contentId(sid);
            if (!inited.has(id)) break;
            const props = event.properties || {};
            const tokens = props.tokens || {};
            const cost = props.cost;
            const finish = props.finish || "unknown";
            post("/api/sessions/observations", {
              contentSessionId: id,
              tool_name: "llm_step_completed",
              tool_input: {
                finish_reason: finish,
                tokens_in: tokens.input || 0,
                tokens_out: tokens.output || 0,
                tokens_reasoning: tokens.reasoning || 0,
                tokens_cache: tokens.cache || 0,
                cost: cost || 0,
              },
              tool_response: `LLM step completed: ${finish} | in=${tokens.input || 0} out=${tokens.output || 0} reasoning=${tokens.reasoning || 0} cost=${cost || "?"}`,
              cwd,
            });
            break;
          }

          case "session.deleted": {
            const cid = sessionMap.get(sid);
            if (cid) inited.delete(cid);
            sessionMap.delete(sid);
            // Clean up any pending message timers
            for (const [key, timer] of msgTimers) {
              if (key.startsWith(`${sid}:`)) {
                clearTimeout(timer);
                msgTimers.delete(key);
              }
            }
            break;
          }
        }
      } catch {}
    },

    // Search tool
    tool: {
      claude_mem_search: {
        description: "Search claude-mem memory database for past observations, sessions, and context",
        args: {
          query: z.string().describe("Search query for memory observations"),
        },
        async execute(args) {
          try {
            const q = String(args.query || "");
            if (!q) return "Please provide a search query.";
            const text = await getText(
              `/api/observations?q=${encodeURIComponent(q)}&limit=10`
            );
            if (!text) return "claude-mem worker is not running.";
            const data = JSON.parse(text);
            const items = Array.isArray(data.items) ? data.items : [];
            if (!items.length) return `No results found for "${q}".`;
            return items.slice(0, 10).map((item, i) => {
              const title = String(item.title || item.subtitle || "Untitled");
              const body = item.narrative || item.text || "";
              const snippet = body.length > 200 ? body.slice(0, 200) + "…" : body;
              return `${i + 1}. **${title}**\n   ${snippet}`;
            }).join("\n\n");
          } catch {
            return "Failed to search claude-mem.";
          }
        },
      },
    },
  };
};

export default ClaudeMemPlugin;
