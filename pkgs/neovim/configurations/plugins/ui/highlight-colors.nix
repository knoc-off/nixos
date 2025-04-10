{
  plugins.highlight-colors = {
    enable = true;

    # Choose rendering style (background, foreground, or virtual)
    render = "background";

    # Virtual text configuration (applies when render = "virtual")
    virtual_symbol = "■";
    virtual_symbol_prefix = "";
    virtual_symbol_suffix = " ";
    virtual_symbol_position = "inline";

    # Enable various color formats
    enable_hex = true;
    enable_short_hex = true;
    enable_rgb = true;
    enable_hsl = true;
    enable_ansi = true;
    enable_hsl_without_function = true;
    enable_var_usage = true;
    enable_named_colors = true;
    enable_tailwind = true;

    # Custom colors (with properly escaped labels)
    custom_colors = [
      {
        label = "%-%-primary%-color";
        color = "#3498db";
      }
      {
        label = "%-%-secondary%-color";
        color = "#2ecc71";
      }
      {
        label = "%-%-accent%-color";
        color = "#e74c3c";
      }
      {
        label = "%-%-background%-dark";
        color = "#1a1a2e";
      }
      {
        label = "%-%-text%-light";
        color = "#f0f0f0";
      }
    ];

    # Exclude certain filetypes or buftypes from highlighting
    exclude_filetypes = [ "NvimTree" "TelescopePrompt" "lazy" ];
    exclude_buftypes = [ "nofile" "terminal" ];

    # Enable integration with nvim-cmp
    cmpIntegration = true;
  };
}
