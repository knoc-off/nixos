{pkgs, ...}: {
  config = {
    globals = {
      # Disable useless providers
      loaded_ruby_provider = 0; # Ruby
      loaded_perl_provider = 0; # Perl
      loaded_python_provider = 0; # Python 2
    };

    clipboard = {
      # clipboard
      register = "unnamedplus"; # is the selection register

      providers.wl-copy.enable = pkgs.stdenv.isLinux;
      # darwin?
      # providers.
    };

    opts = {
      updatetime = 100; # Faster completion

      # Line numbers
      relativenumber = true; # Relative line numbers
      number = true; # Display the absolute line number of the current line
      hidden = true; # Keep closed buffer open in the background
      mouse = "a"; # Enable mouse control
      #mouse = ""; # Disable mouse control
      mousemodel = "extend"; # Mouse right-click extends the current selection
      mousescroll = "ver:1,hor:1"; # Smooth 1-line-at-a-time scrolling, no horizontal
      splitbelow = true; # A new window is put below the current one
      splitright = true; # A new window is put right of the current one

      swapfile = false; # Disable the swap file
      modeline = true; # Tags such as 'vim:ft=sh'
      modelines = 100; # Sets the type of modelines
      undofile = true; # Automatically save and restore undo history
      incsearch = true; # Incremental search: show match for partly typed search command
      ignorecase = true; # When the search query is lower-case, match both lower and upper-case
      #   patterns
      smartcase = true; # Override the 'ignorecase' option if the search pattern contains upper
      #   case characters
      scrolloff = 5; # Number of screen lines to show around the cursor
      cursorline = false; # Highlight the screen line of the cursor
      cursorcolumn = false; # Highlight the screen column of the cursor
      signcolumn = "yes"; # Whether to show the signcolumn
      colorcolumn = "100"; # Columns to highlight
      laststatus = 3; # When to use a status line for the last window
      fileencoding = "utf-8"; # File-content encoding for the current buffer
      encoding = "utf-8"; # Encoding used for the terminal
      fileencodings = "utf-8"; # List of file encodings to try when starting to edit a new file
      fileformats = "unix"; # File formats to try when starting to edit a new file
      fileformat = "unix"; # File format of the current buffer
      list = false; # Show invisible characters

      termguicolors = true; # Enables 24-bit RGB color in the |TUI|
      spell = false; # Highlight spelling mistakes (local to window)
      wrap = false; # Prevent text from wrapping

      # Tab options
      tabstop = 4; # Number of spaces a <Tab> in the text stands for (local to buffer)
      shiftwidth = 2; # Number of spaces used for each step of (auto)indent (local to buffer)
      softtabstop = 0; # If non-zero, number of spaces to insert for a <Tab> (local to buffer)
      expandtab = true; # Expand <Tab> to spaces in Insert mode (local to buffer)
      autoindent = true; # Do clever autoindenting

      textwidth = 0; # Maximum width of text that is being inserted.  A longer line will be
      #   broken after white space to get this width.

      # Folding
      foldlevel = 99; # Folds with a level higher than this number will be closed

      # Tab behavior - open buffers in new tabs by default
      switchbuf = "usetab,newtab"; # Jump to existing tab if buffer is open, otherwise open new tab
    };
  };
}
