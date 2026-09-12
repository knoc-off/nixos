{ pkgs, ... }: {
  globals = {
    # Disable useless providers
    loaded_ruby_provider = 0;
    loaded_perl_provider = 0;
    loaded_python_provider = 0;
  };

  clipboard = {
    register = "unnamedplus";
    providers.wl-copy.enable = pkgs.stdenv.hostPlatform.isLinux;
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

    # Jumplist: browser-style Back/Forward (new jumps truncate forward history)
    # and restore scroll position, not just the cursor line, on <C-o>/<C-i>.
    jumpoptions = "stack,view";
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

  # Never persist undo history for files under a temp dir. `sops edit` decrypts
  # to /tmp/<random>/<name>.yaml and hands that path to $EDITOR, so with the
  # global `undofile` on, every secret edited this way left its plaintext --
  # including every intermediate state -- in an undofile under stdpath("state").
  # Same applies to `git commit` messages, `crontab -e`, and similar temp-file
  # editor handoffs. Matching on path keeps this independent of sops.
  #
  # BufReadPre/BufNewFile fires before the undofile would be read or written.
  # (`swapfile` is already globally off above, so it needs no guard here.)
  autoCmd = [
    {
      event = [
        "BufReadPre"
        "BufNewFile"
      ];
      pattern = [
        "/tmp/*"
        "/var/tmp/*"
        "/dev/shm/*"
      ];
      callback.__raw = ''
        function(args)
          -- ponytail: path-prefix match only; a TMPDIR outside these three
          -- roots is not covered. Add it here if that ever matters.
          vim.bo[args.buf].undofile = false
          vim.bo[args.buf].swapfile = false
        end
      '';
      desc = "No undo/swap persistence for temp-dir buffers (sops edit, git commit, ...)";
    }
  ];
}
