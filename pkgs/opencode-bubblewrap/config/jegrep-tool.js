// OpenCode plugin: semantic code search + a nudge away from bash for file work.
//
//   search            -- jegrep (pkgs/jegrep) as a first-class tool. jegrep is
//                        on the jail PATH and TYPESAFE_API_KEY is injected at
//                        launch (pkgs/opencode-bubblewrap/default.nix).
//   tool.execute.after -- when a bash command starts with cat/rg/find/... ,
//                        append a reminder to use Read/Grep/Glob/search. The
//                        command still runs; this is a nudge, not a block.
//
// Only a default export: opencode's legacy loader calls EVERY export as a
// plugin (plugin/index.ts getLegacyPlugins). nudgeFor is reached by tests as
// a property of the default export instead.

import { execFile } from "node:child_process";
import { createRequire } from "node:module";
import path from "node:path";

// First word of a `&&`/`||`/`;`-separated segment -> the tool to use instead.
// Only segment heads count, so `git log | grep foo` is left alone.
const NUDGES = {
  cat: "Read", head: "Read", tail: "Read", less: "Read", bat: "Read",
  grep: "Grep or search", rg: "Grep or search", jegrep: "search",
  find: "Glob", fd: "Glob", ls: "Glob or Read (Read lists directories)", tree: "Glob",
  sed: "Edit", awk: "Edit",
};

// Pure: command string -> reminder text, or "" when no nudge applies.
// ponytail: first-word heuristic, no shell parser; quoted `&&` inside strings
// can mis-split. Fine for a reminder.
function nudgeFor(command) {
  const hits = new Set();
  for (const seg of String(command).split(/&&|\|\||;|\n/)) {
    const words = seg.trim().split(/\s+/);
    // Skip leading env assignments: `FOO=1 rg ...`
    let i = 0;
    while (i < words.length && /^\w+=/.test(words[i])) i++;
    const cmd = words[i];
    if (!cmd || !(cmd in NUDGES)) continue;
    // sed/awk only matter when editing in place / redirecting into a file.
    if ((cmd === "sed" || cmd === "awk") && !/(\s-i\b|>)/.test(seg)) {
      if (cmd === "sed" && /\s-n\b/.test(seg)) hits.add(`\`sed -n\` -> use Read`);
      continue;
    }
    hits.add(`\`${cmd}\` -> use ${NUDGES[cmd]}`);
  }
  if (!hits.size) return "";
  return (
    "<system-reminder>Bash is for builds, git, nix, tests and running programs. " +
    `For file work use the dedicated tools: ${[...hits].join("; ")}.</system-reminder>`
  );
}

const DESCRIPTION = `Semantic code search: find code by describing what you're looking for in plain language. Your default opening move for any search.

- Fire it early and liberally, especially when in doubt. One call (~1s, ~$0.001) gets you a map of where things live; then follow up with exact Grep and narrow Reads. It is cheaper than even one wrong guess at an identifier.
- Use it for "where/how/what handles X", unfamiliar code, before a Task dispatch, and to find the right file before an exact Grep. Several calls with different phrasings in one message are fine.
- Returns ranked hits, one per line: \`path<TAB>score<TAB>start-end,start-end\`. Read those line ranges narrowly.
- It ranks, it does not enumerate: it may omit matches. Once it has oriented you, use Grep for exact strings, regex, or EVERY occurrence (renames, "no other call sites" checks).
- No/weak hits? Rephrase, narrow \`path\`, or add \`keywords\` you already know.`;

// Appended to native Grep's description so the nudge is there at the moment
// the model picks a search tool.
const GREP_NOTE =
  "\n- Not sure yet where to look? Call `search` first (semantic, ~1s) to get a map, then Grep exactly. Grep is for when you know the string.";

export default async function plugin() {
  const require = createRequire(
    (process.env.HOME || "/root") + "/.config/opencode/package.json"
  );
  const { z } = require("zod");

  return {
    tool: {
      search: {
        description: DESCRIPTION,
        args: {
          query: z.string().describe("What you're looking for, in plain language"),
          path: z
            .string()
            .optional()
            .describe("Directory to search. Defaults to the current working directory."),
          keywords: z
            .array(z.string())
            .optional()
            .describe("Identifiers or literals you already know, to sharpen the lexical pre-filter"),
          hidden: z.boolean().optional().describe("Include dotfiles and dot-directories"),
        },
        async execute(args, ctx) {
          const query = String(args.query || "").trim();
          if (!query) return "Error: empty query";
          await ctx.ask({ permission: "search", patterns: [query], always: ["*"], metadata: { query, path: args.path } });

          const dir = path.resolve(ctx.directory, args.path || ".");
          const argv = [query, dir, "--compact", "-q"];
          if (args.keywords?.length) argv.push("-k", args.keywords.join(","));
          if (args.hidden) argv.push("--hidden");

          const { out, err } = await new Promise((resolve) =>
            execFile(
              "jegrep",
              argv,
              { signal: ctx.abort, timeout: 120_000, maxBuffer: 4 << 20 },
              (err, stdout, stderr) => resolve({ out: stdout, err: err && (stderr || err.message) })
            )
          );
          if (err && !out) return `jegrep failed: ${String(err).trim()}`;

          // jegrep prints hit paths relative to the search root, not the
          // session cwd; make them absolute so they can go straight to Read.
          const lines = out.split("\n").map((l) =>
            l.includes("\t") ? path.join(dir, l.slice(0, l.indexOf("\t"))) + l.slice(l.indexOf("\t")) : l
          );
          const matches = lines.filter((l) => l.includes("\t")).length;
          return { title: query, output: lines.join("\n").trim() || "No results", metadata: { matches } };
        },
      },
    },

    "tool.definition": async (input, output) => {
      if (input.toolID === "grep") output.description += GREP_NOTE;
    },

    "tool.execute.after": async (input, output) => {
      if (input.tool !== "bash") return;
      const nudge = nudgeFor(input.args?.command);
      if (nudge) output.output = `${output.output}\n\n${nudge}`;
    },
  };
}
plugin.nudgeFor = nudgeFor;
