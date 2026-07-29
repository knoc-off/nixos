--- `:checkhealth rhizome`
---
--- Every failure mode here is one that otherwise shows up as an opaque error in
--- the middle of editing: a binary that is not on PATH, a token command that
--- does not run, a server that is not reachable.

local M = {}

local function run(cmd, env)
  -- The token goes through the environment, never argv: anything in argv is
  -- readable by every process on the machine via `ps`.
  local result = vim.system(cmd, { env = env, text = true }):wait()
  return result.code == 0, (result.stdout or "") .. (result.stderr or "")
end

function M.check()
  vim.health.start("rhizome")

  local ok, rhizome = pcall(require, "rhizome")
  if not ok then
    vim.health.error("cannot load the rhizome module")
    return
  end

  local bin = rhizome.resolve_bin()
  if vim.fn.executable(bin) == 1 then
    local _, version = run({ bin, "--version" })
    vim.health.ok("binary: " .. vim.trim(version))
  else
    vim.health.error("binary '" .. bin .. "' not found on PATH")
    return
  end

  local url = rhizome.resolve_url()
  if url then
    vim.health.ok("server url: " .. url)
  else
    vim.health.error("no server url", { "set opts.url, or export $" .. rhizome.url_env() })
  end

  local token_ok, token = pcall(rhizome.resolve_token)
  if not token_ok then
    vim.health.error("token: " .. tostring(token))
    return
  elseif not token then
    vim.health.error("no ETAPI token", {
      "set opts.token_cmd, or export $" .. rhizome.token_env(),
      "the variable must be visible to the process running Neovim, not just to your shell",
    })
    return
  end
  vim.health.ok(("ETAPI token resolved from $%s (%d characters)"):format(
    rhizome.token_env(),
    #token
  ))
  if not url then
    return
  end

  -- Reaching the server is the only check that proves the token is real. This
  -- goes through the same client the LSP server uses, so a pass here means the
  -- editor will connect too.
  local reachable, body = run({ bin, "doctor" }, {
    RHIZOME_URL = url,
    RHIZOME_TOKEN = token,
  })
  local decoded_ok, report = pcall(vim.json.decode, vim.trim(body))
  if decoded_ok and report.ok then
    vim.health.ok("connected to Trilium " .. tostring(report.appVersion))
  elseif decoded_ok then
    vim.health.error("cannot reach the server: " .. tostring(report.error))
  else
    vim.health.error(
      ("doctor failed (exit %s): %s"):format(reachable and 0 or 1, vim.trim(body))
    )
  end
end

return M
