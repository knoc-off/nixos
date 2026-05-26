// OpenCode plugin for claude-mem worker
// Uses OpenCode's flat-key plugin API to send observations to the claude-mem HTTP worker.

function resolveWorkerPort() {
  const fromEnv = process.env.CLAUDE_MEM_WORKER_PORT;
  const parsed = fromEnv ? parseInt(fromEnv.trim(), 10) : NaN;
  if (Number.isInteger(parsed) && parsed >= 1 && parsed <= 65535) return parsed;
  const uid = typeof process.getuid === "function" ? process.getuid() : 77;
  return 37700 + (uid % 100);
}

const WORKER_BASE = `http://127.0.0.1:${resolveWorkerPort()}`;
const MAX_LEN = 1000;
const JSON_HEADERS = { "Content-Type": "application/json" };

function post(path, body) {
  fetch(`${WORKER_BASE}${path}`, {
    method: "POST",
    headers: JSON_HEADERS,
    body: JSON.stringify(body),
  }).catch(() => {});
}

async function getText(path) {
  try {
    const r = await fetch(`${WORKER_BASE}${path}`, { headers: JSON_HEADERS });
    return r.ok ? await r.text() : null;
  } catch {
    return null;
  }
}

const sessionIds = new Map();
function sid(openCodeId) {
  if (!sessionIds.has(openCodeId)) {
    if (sessionIds.size >= 500) sessionIds.delete(sessionIds.keys().next().value);
    sessionIds.set(openCodeId, `opencode-${openCodeId}-${Date.now()}`);
  }
  return sessionIds.get(openCodeId);
}

// Track which sessions have been init'd
const initedSessions = new Set();

function ensureInit(sessionID, project, cwd) {
  const id = sid(sessionID);
  if (!initedSessions.has(id)) {
    initedSessions.add(id);
    post("/api/sessions/init", { contentSessionId: id, project, prompt: "" });
  }
  return id;
}

export const ClaudeMemPlugin = async (ctx) => {
  const project = ctx.project?.name || "opencode";
  const cwd = ctx.directory;

  return {
    // After each tool call, record an observation
    "tool.execute.after": (input, output) => {
      const id = ensureInit(input.sessionID, project, cwd);
      let text = output.output || "";
      if (text.length > MAX_LEN) text = text.slice(0, MAX_LEN);
      post("/api/sessions/observations", {
        contentSessionId: id,
        tool_name: input.tool,
        tool_input: input.args || {},
        tool_response: text,
        cwd,
      });
    },

    // On compaction, send summarize to worker
    "experimental.session.compacting": (input, output) => {
      const sessionID = input.sessionID || input.session?.id;
      if (sessionID) {
        const id = ensureInit(sessionID, project, cwd);
        // Push context so worker gets a chance to inject memory
        // Also fire summarize in the background
        post("/api/sessions/summarize", {
          contentSessionId: id,
          last_assistant_message: output.prompt || "",
        });
      }
    },

    // Custom search tool
    tool: {
      claude_mem_search: {
        description: "Search claude-mem memory database for past observations, sessions, and context",
        args: {
          query: { type: "string", description: "Search query for memory observations" },
        },
        async execute(args) {
          const q = String(args.query || "");
          if (!q) return "Please provide a search query.";
          const text = await getText(`/api/search/observations?query=${encodeURIComponent(q)}&limit=10`);
          if (!text) return "claude-mem worker is not running.";
          try {
            const data = JSON.parse(text);
            const items = Array.isArray(data.items) ? data.items : [];
            if (!items.length) return `No results found for "${q}".`;
            return items.slice(0, 10).map((item, i) => {
              const title = String(item.title || item.subtitle || "Untitled");
              const proj = item.project ? ` [${item.project}]` : "";
              return `${i + 1}. ${title}${proj}`;
            }).join("\n");
          } catch {
            return "Failed to parse search results.";
          }
        },
      },
    },
  };
};

export default ClaudeMemPlugin;
