{pkgs, ...}: {
  globals = {
    # Disable useless providers
    loaded_ruby_provider = 0;
    loaded_perl_provider = 0;
    loaded_python_provider = 0;
  };

  clipboard = {
    register = "unnamedplus";
    providers.wl-copy.enable = pkgs.stdenv.isLinux;
  };

  opts = {
    updatetime = 100;

    # Line numbers
    relativenumber = true;
    number = true;
    hidden = true;
    mouse = "a";
    mousemodel = "extend";
    mousescroll = "ver:1,hor:1";
    splitbelow = true;
    splitright = true;

    swapfile = false;
    modeline = true;
    modelines = 100;
    undofile = true;
    incsearch = true;
    ignorecase = true;
    smartcase = true;
    scrolloff = 5;
    scroll = 8;
    cursorcolumn = false;
    signcolumn = "yes";
    colorcolumn = "100";
    laststatus = 3;
    fileencoding = "utf-8";
    encoding = "utf-8";
    fileencodings = "utf-8";
    fileformats = "unix";
    fileformat = "unix";
    list = false;

    termguicolors = true;
    spell = false;
    wrap = false;

    # Tab/indent (consistent: 2 spaces everywhere)
    tabstop = 2;
    shiftwidth = 2;
    softtabstop = 2;
    expandtab = true;
    autoindent = true;

    textwidth = 0;

    # Folding via treesitter
    foldmethod = "expr";
    foldexpr = "v:lua.vim.treesitter.foldexpr()";
    foldlevel = 99;
    foldlevelstart = 99;
    foldtext = "";

    foldenable = true;
    # gf extension fallback
    suffixesadd = ".md,.txt,.nix";
  };
}
