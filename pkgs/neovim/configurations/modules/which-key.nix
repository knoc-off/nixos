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
        # Bare `g` prefix: LSP navigation (gd/gr/gi/gt), buffer-local on LSP attach
        { __unkeyed = "g"; group = "Go"; }
        { __unkeyed = "<leader>b"; group = "Buffers"; }
        { __unkeyed = "<leader>c"; group = "Code"; }
        { __unkeyed = "<leader>d"; group = "Diagnostics"; }
        { __unkeyed = "<leader>f"; group = "Find"; }
        { __unkeyed = "<leader>g"; group = "Git"; }
        { __unkeyed = "<leader>l"; group = "LSP"; }
        { __unkeyed = "<leader>r"; group = "Rust"; }
        { __unkeyed = "<leader>s"; group = "Session/Split"; }
        { __unkeyed = "<leader>S"; group = "Sessions (load)"; }
        { __unkeyed = "<leader>t"; group = "Trouble"; }
        { __unkeyed = "<leader>v"; group = "Visits"; }
      ];
    };
  };
}
