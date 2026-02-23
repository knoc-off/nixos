# OpenSCAD development environment
# - openscad_lsp (LSP)
# - Auto-launch OpenSCAD viewer on .scad files
{lib, ...}: {
  plugins.lsp.servers.openscad_lsp.enable = true;

  autoCmd = [
    # Launch OpenSCAD when opening .scad files
    {
      event = "BufWinEnter";
      pattern = "*.scad";
      callback = lib.nixvim.mkRaw ''
        function(args)
          if vim.b[args.buf].openscad_job then
            return
          end

          local filepath = vim.fn.expand('%:p')
          local jid = vim.fn.jobstart(
            { "openscad", filepath },
            {
              detach = true,
              on_stdout = function() end,
              on_stderr = function() end,
            }
          )

          vim.b[args.buf].openscad_job = jid
          vim.notify(
            'Launched OpenSCAD for ' .. vim.fn.fnamemodify(filepath, ':t'),
            vim.log.levels.INFO
          )
        end
      '';
    }

    # Close OpenSCAD when leaving .scad files
    {
      event = "BufWinLeave";
      pattern = "*.scad";
      callback = lib.nixvim.mkRaw ''
        function(args)
          local jid = vim.b[args.buf].openscad_job
          if jid then
            vim.fn.jobstop(jid)
            vim.b[args.buf].openscad_job = nil
            vim.notify(
              'Closed OpenSCAD for ' .. vim.fn.fnamemodify(vim.fn.expand('%:p'), ':t'),
              vim.log.levels.INFO
            )
          end
        end
      '';
    }

    # Clean up any remaining OpenSCAD processes on Neovim exit
    {
      event = "VimLeavePre";
      pattern = "*";
      callback = lib.nixvim.mkRaw ''
        function()
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            local ok, jid = pcall(vim.api.nvim_buf_get_var, buf, 'openscad_job')
            if ok and jid then
              pcall(vim.fn.jobstop, jid)
            end
          end
        end
      '';
    }
  ];
}
