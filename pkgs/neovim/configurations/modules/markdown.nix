# Markdown concealing
#
# Neovim's own markdown queries already carry the conceal metadata -- see
# `queries/markdown/highlights.scm` (`fenced_code_block_delimiter` and the
# `info_string` language both get `conceal ""` *and* `conceal_lines ""`). All
# that is missing is `conceallevel`, which defaults to 0 and makes the runtime
# ignore every one of those captures. This is the same machinery that renders
# LSP hover floats, where `vim/lsp/util.lua` sets `conceallevel = 2`.
{ ... }: {
  autoCmd = [
    {
      # `conceallevel`/`concealcursor` are window-local, so `FileType` alone is
      # not enough: displaying an already-loaded markdown buffer in a window
      # that never saw the event (`:b notes.md` in an existing split) leaves it
      # at 0. `BufWinEnter` covers those windows.
      event = [
        "FileType"
        "BufWinEnter"
      ];
      pattern = [ "*" ];
      callback.__raw = ''
        function(args)
          if vim.bo[args.buf].filetype ~= "markdown" then
            return
          end
          -- Rhizome's Trilium buffers are `filetype = "markdown"` too, but they
          -- manage `conceallevel`/`concealcursor` themselves in lockstep with
          -- the link-title virtual text. Racing that draws the raw text and the
          -- title at once, so leave those buffers alone.
          if vim.api.nvim_buf_get_name(args.buf):match("^trilium://") then
            return
          end
          vim.wo.conceallevel = 2
          -- Concealed in normal and command-line mode, revealed in insert and
          -- visual. `conceal_lines` removes the fence line from the display
          -- entirely rather than blanking it, so the cursor can rest on a line
          -- that is not drawn -- the visual-mode reveal is what makes operating
          -- on a fence (or a collapsed link) something you can still see.
          vim.wo.concealcursor = "nc"
        end
      '';
    }
  ];
}
