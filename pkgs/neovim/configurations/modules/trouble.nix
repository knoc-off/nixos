# trouble.nvim - persistent, grouped results panel (the "Find Usages tool window").
#
# Deliberately complements mini.pick rather than replacing it:
#   * mini.pick (gd/gr/gi/gt) = fast, transient "jump to one result".
#   * trouble (<leader>t...)  = dockable panel, grouped by file, with preview,
#     that stays open while you walk through every result methodically.
# Also provides the call hierarchy (incoming/outgoing) that has no usable raw UI.
{lib, ...}: {
  plugins.trouble.enable = true;

  keymaps = let
    mk = key: cmd: desc: {
      mode = "n";
      inherit key;
      action = "<cmd>Trouble ${cmd}<cr>";
      options = {
        silent = true;
        inherit desc;
      };
    };
  in [
    (mk "<leader>tr" "lsp_references toggle focus=true" "References (panel)")
    (mk "<leader>ts" "lsp toggle focus=false win.position=right" "LSP defs/refs/impl")
    (mk "<leader>td" "diagnostics toggle" "Diagnostics (project)")
    (mk "<leader>tD" "diagnostics toggle filter.buf=0" "Diagnostics (buffer)")
    (mk "<leader>ty" "symbols toggle focus=false win.position=right" "Symbols (outline)")
    (mk "<leader>ti" "lsp_incoming_calls toggle focus=true" "Incoming calls")
    (mk "<leader>to" "lsp_outgoing_calls toggle focus=true" "Outgoing calls")
    (mk "<leader>tq" "qflist toggle" "Quickfix list")
    (mk "<leader>tl" "loclist toggle" "Location list")
    (mk "<leader>tx" "toggle" "Toggle last panel")
  ];
}
