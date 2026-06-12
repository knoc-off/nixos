# Text objects via mini.ai and hardtime for building good habits
{...}: {
  # Provides the @function/@class/@conditional/@loop treesitter queries that
  # mini.ai consumes below. Its own select/move/swap mappings stay off so they
  # don't fight mini.ai over the a/i keys.
  plugins.treesitter-textobjects.enable = true;

  plugins.mini = {
    enable = true;
    modules.ai = {
      # Scope-style objects keyed to the same treesitter nodes the IBL scope
      # highlight uses. mini.ai stays the sole owner of a/i, avoiding conflicts.
      #   viF/vaF -> function   vic/vac -> class   vio/vao -> conditional/loop
      custom_textobjects.__raw = ''
        {
          F = require("mini.ai").gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
          c = require("mini.ai").gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
          o = require("mini.ai").gen_spec.treesitter({
            a = { "@conditional.outer", "@loop.outer" },
            i = { "@conditional.inner", "@loop.inner" },
          }),
        }
      '';
    };
  };

  plugins.hardtime.enable = false;
}
