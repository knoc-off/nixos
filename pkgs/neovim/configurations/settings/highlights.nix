{
  helpers,
  lib,
  ...
}: {
  # Highlight and remove extra white spaces
  match.ExtraWhitespace = "\\s\\+$";
  highlight.ExtraWhitespace.bg = "#242628";

  highlight.Todo = {
    fg = "Blue";
    bg = "Yellow";
  };

  match.TODO = "TODO";

  keymaps = [
    {
      mode = "n";
      key = "<C-t>";
      action = helpers.mkRaw ''
        function()
          require('telescope.builtin').live_grep({
            default_text="TODO",
            initial_mode="normal"
          })
        end
      '';
      options.silent = true;
    }
  ];
}
