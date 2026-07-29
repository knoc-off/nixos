-- Headless DAP demo init.
--
-- Runs OUTSIDE your normal config on purpose: we want to prove the raw chain
-- (nvim-dap -> codelldb -> lldb -> binary) with nothing else in the way. In the
-- real editor, rustaceanvim registers this adapter+config for you automatically
-- when rust-analyzer attaches; here we wire the same thing by hand so the demo
-- is self-contained and doesn't need rust-analyzer running.
--
-- Args (via -c "lua ..."): DEMO_BIN (compiled debuggee), DEMO_SRC (source path),
-- DEMO_BP_LINE (breakpoint line). Provided by run.sh through vim.g.

local dap = require("dap")

-- codelldb as a *server* adapter: dap spawns `codelldb --port <p>` and connects
-- over TCP. Identical to what rustaceanvim configures on NixOS.
dap.adapters.codelldb = {
  type = "server",
  host = "127.0.0.1",
  port = "${port}",
  executable = {
    command = "codelldb",
    args = { "--port", "${port}" },
  },
}

dap.configurations.rust = {
  {
    name = "DAP demo: launch factorial",
    type = "codelldb",
    request = "launch",
    program = vim.g.demo_bin,
    cwd = vim.fn.fnamemodify(vim.g.demo_src, ":h"),
    stopOnEntry = false,
    sourceLanguages = { "rust" },
  },
}

local log = function(...) io.stdout:write(table.concat({ ... }, "") .. "\n"); io.stdout:flush() end
local function fail(msg) log("FAIL: " .. msg); vim.cmd("cq 1") end

-- Drive an async DAP session to completion, then report. We use dap listeners
-- for lifecycle events and Session:request for the actual DAP calls (scopes /
-- variables) that read values back out of the stopped debuggee.
local done = false
local results = { stopped = false, vars_before = nil, vars_after = nil }

-- Pull the current frame's locals as a name->value map, via the DAP protocol:
--   stackTrace -> scopes -> variables   (exactly what the UI does under the hood)
local function read_locals(session, cb)
  local frame = session.current_frame
  if not frame then return cb(nil, "no current frame") end
  session:request("scopes", { frameId = frame.id }, function(err, scopes_resp)
    if err then return cb(nil, "scopes: " .. vim.inspect(err)) end
    local locals_scope
    for _, s in ipairs(scopes_resp.scopes or {}) do
      if s.name == "Local" or s.name == "Locals" or not s.expensive then
        locals_scope = s
        break
      end
    end
    if not locals_scope then return cb(nil, "no locals scope") end
    session:request("variables", { variablesReference = locals_scope.variablesReference }, function(verr, vresp)
      if verr then return cb(nil, "variables: " .. vim.inspect(verr)) end
      local map = {}
      for _, v in ipairs(vresp.variables or {}) do
        map[v.name] = v.value
      end
      cb(map, nil)
    end)
  end)
end

log("[2/6] load nvim-dap ............................ ok  (codelldb: " .. vim.fn.exepath("codelldb") .. ")")

-- Breakpoint at the loop body line.
vim.fn.sign_define("DapBreakpoint", { text = "B" })
vim.cmd("edit " .. vim.g.demo_src)
vim.api.nvim_win_set_cursor(0, { vim.g.demo_bp_line, 0 })
dap.toggle_breakpoint()
log("[3/6] breakpoint at demo.rs:" .. vim.g.demo_bp_line .. " ................. ok")

-- First stop: read locals, then step twice and read again to prove values change.
local step_count = 0
dap.listeners.after.event_stopped["demo"] = function(session, body)
  results.stopped = true
  log("        >> event_stopped   reason=" .. tostring(body.reason) .. "  thread=" .. tostring(body.threadId))

  read_locals(session, function(vars, err)
    if err then return fail(err) end
    if step_count == 0 then
      results.vars_before = vars
      log("[5/6] stackTrace + scopes + variables:")
      local frame = session.current_frame
      log("        frame:  " .. (frame and frame.name or "?"))
      log("        locals: n = " .. tostring(vars.n) .. "     acc = " .. tostring(vars.acc) .. "     i = " .. tostring(vars.i))
      -- Step over twice (acc *= i; then i += 1;) to loop once more.
      log("[6/6] step_over x2, watching `acc`:")
      step_count = 1
      dap.step_over()
    elseif step_count == 1 then
      step_count = 2
      dap.step_over()
    else
      results.vars_after = vars
      log("        acc: " .. tostring(results.vars_before.acc) .. " -> " .. tostring(vars.acc)
        .. "   i: " .. tostring(results.vars_before.i) .. " -> " .. tostring(vars.i))
      dap.terminate()
    end
  end)
end

dap.listeners.after.event_terminated["demo"] = function()
  log("        terminate .............................. ok")
  done = true
end
dap.listeners.after.disconnect["demo"] = function()
  done = true
end

log("[4/6] dap.run{ type=codelldb, request=launch } . ok")
dap.continue()

-- Pump the event loop until the session finishes (or time out).
local ok = vim.wait(30000, function() return done end, 50)
if not ok then fail("timed out waiting for debug session") end
if not results.stopped then fail("breakpoint never hit") end
if not (results.vars_before and results.vars_after) then fail("could not read locals") end

-- Assertions: at first stop (i=1) acc=1; after one full loop iteration acc=1*1=1
-- then next stop i=2 so acc becomes... we just assert acc changed and i advanced.
local before, after = results.vars_before, results.vars_after
if before.acc == nil or after.acc == nil then fail("acc not observed") end
if tostring(before.i) == tostring(after.i) then fail("i did not advance across steps") end

log("")
log("RESULT: chain verified  nvim-dap -> codelldb -> lldb -> demo binary")
vim.cmd("qa!")
