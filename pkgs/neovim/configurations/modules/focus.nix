# Focus signaling for active window
# Makes it obvious which window/buffer is active
{lib, ...}: {
  # Enable cursorline globally (we'll toggle it per-window via autocmd)
  opts = {
    cursorline = true;
    cursorlineopt = "both";
  };

  autoCmd = [
    {
      event = ["WinEnter" "BufEnter" "FocusGained"];
      pattern = "*";
      callback = lib.nixvim.mkRaw ''
        function()
          vim.wo.cursorline = true
          vim.wo.winhighlight = ""
        end
      '';
      desc = "Highlight active window";
    }
    {
      event = ["WinLeave" "BufLeave" "FocusLost"];
      pattern = "*";
      callback = lib.nixvim.mkRaw ''
        function()
          vim.wo.cursorline = false
          vim.wo.winhighlight = "Normal:DimInactive,NormalNC:DimInactive,CursorLineNr:DimInactive,SignColumn:DimInactive,EndOfBuffer:DimInactive"
        end
      '';
      desc = "Dim inactive window";
    }
  ];

  highlightOverride = {
    DimInactive = {
      bg = "none";
      fg = "#666666";
      blend = 30;
    };
  };
}
