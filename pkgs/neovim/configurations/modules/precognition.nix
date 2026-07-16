# precognition.nvim in peek-only mode: a "tap to reveal" HUD of the default
# motions available from the cursor (w/b/e, ^/$/%, gutter G/gg/{/}).
#
# It stays fully dormant (startVisible=false) so normal editing is unaffected.
#   <leader>?   peek: show hints on the current line once; they auto-clear the
#               moment the cursor moves, insert mode starts, or you leave the buf.
# Complements flash (labelled jumps on s/S) -- this is a passive hint HUD, not a
# jump motion, so there is no key or behaviour overlap.
{...}: {
  plugins.precognition = {
    enable = true;
    settings = {
      startVisible = false; # dormant until peeked
      showBlankVirtLine = false; # never render empty virtual lines
      highlightColor.link = "Comment"; # subtle, matches muted UI
      # Disable the f/t/F/T per-character targets -- they flood the line with a
      # dense wall of hints and duplicate the native f/t highlighting. Keeps the
      # tidy word/line HUD (w/b/e/^/$/%/0) only.
      targetedMotionHints.enabled = false;
    };
  };

  keymaps = [
    {
      mode = "n";
      key = "<leader>?";
      action = "<cmd>Precognition peek<cr>";
      options.desc = "Peek motion hints";
    }
  ];
}
