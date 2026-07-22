# diffview.nvim - full-window diffs and git history browsing. Complements the
# inline, per-hunk gitsigns workflow (it does the "review the whole changeset /
# browse history / resolve a merge" jobs gitsigns can't).
#
#   <leader>gd  open diff view. During a merge/rebase this lists the conflicted
#               files and opens them in a 3-way conflict layout; otherwise it's
#               a side-by-side diff of the working tree.
#   <leader>gh  browse the current branch's commit history (with diffs).
#   <leader>gH  browse the current file's history.
#   <leader>gq  close the diff view.
#
# <Esc> also closes the diff view from any diffview panel/buffer.
#
# Inside a merge-conflict diff, diffview provides buffer-local keys (no wiring
# needed): co/ct/cb/ca = choose ours/theirs/base/all, ]x / [x = next/prev
# conflict. See `:h diffview-config-keymaps`.
{lib, ...}: {
  # Also an owner of the <leader>g "Git" group; deduplicated against git.nix.
  whichKeyGroups = [{__unkeyed = "<leader>g"; group = "Git";}];

  plugins.diffview = {
    enable = true;
    # <Esc> closes the whole Diffview from any of its panels/diff buffers, in
    # addition to the default `q`. These bindings are buffer-local to diffview,
    # so <Esc> is unaffected everywhere else.
    settings.keymaps = let
      esc = {
        mode = "n";
        key = "<Esc>";
        action = lib.nixvim.mkRaw "function() vim.cmd('DiffviewClose') end";
        description = "Close Diffview";
      };
    in {
      view = [esc];
      file_panel = [esc];
      file_history_panel = [esc];
    };
  };

  keymaps = let
    mk = key: cmd: desc: {
      mode = "n";
      inherit key;
      action = "<cmd>${cmd}<cr>";
      options = {
        silent = true;
        inherit desc;
      };
    };
  in [
    # Diff view against the shared GitState base (same as gutter signs /
    # <leader>gl hunks picker), so all diff surfaces stay consistent. During a
    # merge/rebase, open bare so diffview surfaces the 3-way conflict layout.
    {
      mode = "n";
      key = "<leader>gd";
      action = lib.nixvim.mkRaw ''
        function()
          local merging = vim.system(
            { 'git', 'rev-parse', '--verify', '--quiet', 'MERGE_HEAD' }
          ):wait().code == 0
          if merging then
            vim.cmd('DiffviewOpen')
          else
            vim.cmd('DiffviewOpen ' .. _G.GitState.get_base())
          end
        end
      '';
      options = { silent = true; desc = "Diff view / merge conflicts"; };
    }
    (mk "<leader>gh" "DiffviewFileHistory" "Branch history")
    (mk "<leader>gH" "DiffviewFileHistory %" "File history")
    (mk "<leader>gq" "DiffviewClose" "Close diff view")
  ];
}
