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
const MAX_LEN = 1000;
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
          case "message.updated": {
            if (event.properties?.role !== "assistant") break;
            const id = contentId(sid);
            if (!inited.has(id)) break;
            post("/api/sessions/observations", {
              contentSessionId: id,
              tool_name: "assistant_message",
              tool_input: {},
              tool_response: clip(event.properties?.content),
              cwd,
            });
            break;
          }
          case "file.edited": {
            const id = contentId(sid);
            if (!inited.has(id)) break;
            post("/api/sessions/observations", {
              contentSessionId: id,
              tool_name: "file_edit",
              tool_input: { path: event.properties?.path },
              tool_response: clip(event.properties?.diff) || `File edited: ${event.properties?.path}`,
              cwd,
            });
            break;
          }
          case "session.deleted": {
            const cid = sessionMap.get(sid);
            if (cid) inited.delete(cid);
            sessionMap.delete(sid);
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
