# which-key: popup showing available keybinds after pressing a prefix
{...}: {
  plugins.which-key = {
    enable = true;
    settings = {
      delay = 300;
      icons = {
        breadcrumb = ">>";
        separator = "->";
        group = "+";
      };
      spec = [
        { __unkeyed = "<leader>b"; group = "Buffers"; }
        { __unkeyed = "<leader>c"; group = "Code"; }
        { __unkeyed = "<leader>f"; group = "Find"; }
        { __unkeyed = "<leader>g"; group = "Git"; }
        { __unkeyed = "<leader>l"; group = "LSP"; }
        { __unkeyed = "<leader>o"; group = "OpenCode"; }
        { __unkeyed = "<leader>r"; group = "Rust"; }
        { __unkeyed = "<leader>s"; group = "Sessions (save)"; }
        { __unkeyed = "<leader>S"; group = "Sessions (load)"; }
      ];
    };
  };
}
