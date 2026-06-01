// OpenCode plugin for host-query.
// Exposes a single tool that executes commands on the host (outside the jail).
// Permission is set to "ask" so the user always approves each command.

import { createRequire } from "node:module";
const require = createRequire(
  (process.env.HOME || "/root") + "/.config/opencode/package.json"
);
const { z } = require("zod");

const PORT = process.env.HOST_QUERY_PORT || "19600";
const BASE = `http://127.0.0.1:${PORT}`;

export default async (_ctx) => ({
  tool: {
    host_exec: {
      description:
        "Execute a command on the host system (outside the sandbox). " +
        "Use for reading system logs (journalctl), checking service status " +
        "(systemctl status), boot analysis (systemd-analyze), and other " +
        "read-only host queries. The command runs in a shell on the host.",
      args: {
        command: z
          .string()
          .describe(
            "Shell command to run on the host (e.g. 'journalctl -u nginx -n 50', 'systemctl status sshd')"
          ),
      },
      async execute(args, context) {
        const command = String(args.command || "").trim();
        if (!command) return "Error: empty command";

        // Always prompt — never auto-approve (always:[] means "allow until restart" won't skip future prompts)
        await context.ask({
          permission: "host_exec",
          patterns: [command],
          always: [],
          metadata: { command },
        });

        try {
          const r = await fetch(`${BASE}/exec`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ command }),
            signal: AbortSignal.timeout(35000),
          });
          const data = await r.json();

          if (!r.ok) return `Error: ${data.error || r.statusText}`;

          const code =
            data.exit_code !== 0 ? ` (exit ${data.exit_code})` : "";
          return `$ ${data.command}${code}\n${data.output || "(no output)"}`;
        } catch (e) {
          return `host-query service unavailable: ${e.message}`;
        }
      },
    },
  },
});
