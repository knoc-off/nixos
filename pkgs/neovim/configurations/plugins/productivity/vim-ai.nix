{ pkgs, ... }: {
  extraPlugins = with pkgs.vimPlugins;
    [
      (pkgs.vimUtils.buildVimPlugin rec {
        pname = "vim-ai";
        version = "f5163548a5c53cfd19e186d2214533e9ed658f03";
        src = pkgs.fetchFromGitHub {
          owner = "madox2";
          repo = "vim-ai";
          rev = version;
          sha256 = "sha256-W0Xov86RiI3GD+XVVFGWnbrSGJ70rJybA+lrIzscCdM=";
        };
      })
    ];

  extraConfigLua = ''
    -- vim.g.vim_ai_edit = {
    --   options = {
    --     model = "gpt-3.5-turbo",
    --     temperature = 0.2,
    --   },
    -- }
  '';
}
