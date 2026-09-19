// OpenCode plugin for host-query.
// Exposes two tools that act on the host (outside the jail):
//   host_exec  -- run a shell command
//   host_mount -- grant a host directory into the jail (ro by default, rw opt-in)
// Both are permission "ask" so the user approves each one.

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
            // Above the server's own 120s exec budget, so a slow command
            // surfaces the server's timeout error rather than a bare client
            // abort. The budget is generous because a sudo askpass dialog
            // blocks on a human noticing it.
            signal: AbortSignal.timeout(130000),
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

    host_mount: {
      description:
        "Grant a host directory into the sandbox. Use when you need to " +
        "browse, search or edit files outside the mounted projects with " +
        "the normal file tools. The directory appears at " +
        "~/scratch/granted/<name> and stays for the rest of the session. " +
        "Read-only by default; pass write:true to mount it read-write. " +
        "Re-granting an existing name remounts it, so switching a grant to " +
        "writable is just another call.",
      args: {
        path: z
          .string()
          .describe("Absolute host directory to grant (e.g. '/var/lib/foo')"),
        name: z
          .string()
          .optional()
          .describe("Mount name under ~/scratch/granted (default: basename)"),
        write: z
          .boolean()
          .optional()
          .describe("Mount read-write instead of read-only (default: false)"),
      },
      async execute(args, context) {
        const path = String(args.path || "").trim();
        if (!path) return "Error: empty path";
        const name = String(args.name || "").trim();
        const write = Boolean(args.write);

        await context.ask({
          permission: "host_mount",
          patterns: [write ? `${path} (write)` : path],
          always: [],
          metadata: { path, name, write },
        });

        try {
          const r = await fetch(`${BASE}/mount`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ path, ...(name && { name }), write }),
            signal: AbortSignal.timeout(35000),
          });
          const data = await r.json();

          if (!r.ok) return `Error: ${data.error || r.statusText}`;
          const mode = data.mode === "rw" ? "read-write" : "read-only";
          const how = data.remounted ? "Remounted" : "Mounted";
          return `${how} ${data.source} ${mode} at ${data.jail_path}`;
        } catch (e) {
          return `host-query service unavailable: ${e.message}`;
        }
      },
    },
  },
});
