# mini.visits - automatic frecency tracking + named bookmarks ("labels").
# Fills the JetBrains "Bookmarks" + global "recent locations" gap that Vim's
# per-buffer `g;` and unnamed marks don't cover. Visits are auto-registered on
# BufEnter once the module is set up; labels are arbitrary named tags on a file.
#
#   <leader>vv  pick recent files by frecency (all of cwd)
#   <leader>vl  pick by label, then pick a file carrying it
#   <leader>va  add a label to the current file (named bookmark)
#   <leader>vd  remove a label from the current file
#   <leader>vn / <leader>vp  jump to next / previous file by frecency
{lib, ...}: {
  whichKeyGroups = [{__unkeyed = "<leader>v"; group = "Visits";}];

  plugins.mini.modules.visits = {};

  keymaps = let
    mk = key: fn: desc: {
      mode = "n";
      inherit key;
      action = lib.nixvim.mkRaw "function() ${fn} end";
      options = {
        silent = true;
        inherit desc;
      };
    };
  in [
    (mk "<leader>vv" "require('mini.extra').pickers.visit_paths()" "Visits (frecency)")
    (mk "<leader>vl" "require('mini.extra').pickers.visit_labels()" "Visits by label")
    (mk "<leader>va" "require('mini.visits').add_label()" "Add label")
    (mk "<leader>vd" "require('mini.visits').remove_label()" "Remove label")
    (mk "<leader>vn" "require('mini.visits').iterate_paths('forward')" "Next visit")
    (mk "<leader>vp" "require('mini.visits').iterate_paths('backward')" "Previous visit")
  ];
}
