# Statusline via mini.statusline
# Shows mode, file, git branch, diagnostics, LSP, cursor position
{...}: {
  plugins.mini = {
    enable = true;
    modules.statusline = {};
  };
}
