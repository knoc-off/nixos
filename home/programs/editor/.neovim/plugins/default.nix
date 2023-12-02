{
  imports = [
    ./extra.nix

    ./barbar.nix
    ./comment.nix
    ./floaterm.nix
    ./harpoon.nix

    ./lsp
    ./lualine.nix
    ./markdown-preview.nix

    ./neorg.nix
    ./nvim-tree.nix
    ./startify.nix
    ./tagbar.nix
    ./telescope.nix
    ./vimtex.nix

    ./treesitter.nix
  ];

  programs.nixvim = {
    colorscheme = "darkplus";

    plugins = {
      gitsigns = {
        enable = true;
        signs = {
          add.text = "+";
          change.text = "~";
        };
      };

      nvim-autopairs.enable = true;

      nvim-colorizer = {
        enable = true;
        userDefaultOptions.names = false;
      };
    };
  };
}
