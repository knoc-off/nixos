# Keymap builders shared by modules that map many keys to one plugin
# ("<leader>tX" -> ":Trouble X<cr>" etc). Not a general keymap DSL -- just the
# two shapes that recur: an ex-command template, and a Lua call template.
{ lib }: {
  # key -> "<cmd>${cmd}<cr>" in normal mode.
  mkCmd = key: cmd: desc: {
    mode = "n";
    inherit key;
    action = "<cmd>${cmd}<cr>";
    options = {
      silent = true;
      inherit desc;
    };
  };

  # key -> `function() ${fn} end` in normal mode.
  mkFn = key: fn: desc: {
    mode = "n";
    inherit key;
    action = lib.nixvim.mkRaw "function() ${fn} end";
    options = {
      silent = true;
      inherit desc;
    };
  };

  # Same as mkFn, with an explicit mode list instead of a fixed "n".
  mkFnModes = modes: key: fn: desc: {
    mode = modes;
    inherit key;
    action = lib.nixvim.mkRaw "function() ${fn} end";
    options = {
      silent = true;
      inherit desc;
    };
  };
}
