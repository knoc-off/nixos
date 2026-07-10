# flash.nvim - label-based motion (AceJump equivalent). flash ships no default
# keymaps, so we set the conventional ones explicitly:
#   s  jump to any location on screen (normal/visual/operator)
#   S  Treesitter-aware node selection
#   r  remote flash (operator-pending, e.g. `yr` to yank a remote range)
#   R  Treesitter search in operator-pending/visual
# Enabling the plugin also enhances f/F/t/T with labels (flash `char` mode).
{lib, ...}: {
  plugins.flash.enable = true;

  keymaps = let
    mk = modes: key: fn: desc: {
      mode = modes;
      inherit key;
      action = lib.nixvim.mkRaw "function() require('flash').${fn} end";
      options = {
        silent = true;
        inherit desc;
      };
    };
  in [
    (mk ["n" "x" "o"] "s" "jump()" "Flash jump")
    (mk ["n" "x" "o"] "S" "treesitter()" "Flash Treesitter")
    (mk ["o"] "r" "remote()" "Flash remote")
    (mk ["o" "x"] "R" "treesitter_search()" "Flash Treesitter search")
  ];
}
