{
  pkgs,
  lib,
  ...
}: {
    plugins.base16 = {
      enable = true;

      # Define your custom colorscheme here
      colorscheme = {
        # --- Replace these placeholder hex codes with your desired colors ---
        base00 = "#1d2021"; # Default Background
        base01 = "#3c3836"; # Lighter Background (Status Bar)
        base02 = "#504945"; # Selection Background
        base03 = "#665c54"; # Comments, Invisibles, Line Highlighting
        base04 = "#bdae93"; # Dark Foreground (Status Bar)
        base05 = "#d5c4a1"; # Default Foreground, Caret, Delimiters, Operators
        base06 = "#ebdbb2"; # Light Foreground (Not often used)
        base07 = "#fbf1c7"; # Light Background (Not often used)
        base08 = "#fb4934"; # Variables, XML Tags, Markup Link Text, Markup Lists, Diff Deleted
        base09 = "#fe8019"; # Integers, Boolean, Constants, XML Attributes, Markup Link Url
        base0A = "#fabd2f"; # Classes, Markup Bold, Search Text Background
        base0B = "#b8bb26"; # Strings, Inherited Class, Markup Code, Diff Inserted
        base0C = "#8ec07c"; # Support, Regular Expressions, Escape Characters, Markup Quotes
        base0D = "#83a598"; # Functions, Methods, Attribute IDs, Headings
        base0E = "#d3869b"; # Keywords, Storage, Selector, Markup Italic, Diff Changed
        base0F = "#d65d0e"; # Deprecated, Opening/Closing Embedded Language Tags e.g. <?php ?>
        # --- End of custom color definitions ---
      };

      # Optional: Configure integrations (defaults are shown in the plugin definition)
      # settings = {
      #   telescope = true;
      #   telescope_borders = false;
      #   indentblankline = true;
      #   notify = true;
      #   ts_rainbow = true;
      #   cmp = true;
      #   illuminate = true;
      #   lsp_semantic = true;
      #   mini_completion = true;
      #   dapui = true;
      # };

      # Optional: Set to false if you don't want base16 to theme your status bar
      # setUpBar = true;
    };

    # Ensure termguicolors is enabled for base16 to work correctly
    # (The plugin sets this by default, but explicitly setting it doesn't hurt)
    opts.termguicolors = true;

    # Set the colorscheme globally (Nixvim handles applying the base16 config)
    # Although the plugin definition sets `colorscheme = null;` internally
    # to prevent default loading, we still need to tell Vim *which*
    # colorscheme configuration Nixvim should apply.
    colorscheme = "base16";
}
