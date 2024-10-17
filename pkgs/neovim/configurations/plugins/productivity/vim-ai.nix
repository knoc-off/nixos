{ pkgs, ... }: {
  extraPlugins = with pkgs.vimPlugins;
    [
      (pkgs.vimUtils.buildVimPlugin rec {
        pname = "vim-ai";
        version = "758be522e6d765eeb78ce7681f4b39e3b05043b8";
        src = pkgs.fetchFromGitHub {
          owner = "madox2";
          repo = "vim-ai";
          rev = version;
          sha256 = "sha256-hslSD2Z8qFMA3xjKg1bUZlzN8DfIMwA++v03RYWxIDU=";
        };
      })
    ];
}
