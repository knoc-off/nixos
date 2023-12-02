{
  programs.nixvim = {
    globals = {
      # Enable filetype matching using fast `filetype.lua`
      do_filetype_lua = 1;

      # Disable useless providers
      loaded_ruby_provider = 0; # Ruby
      loaded_perl_provider = 0; # Perl
      loaded_python_provider = 0; # Python 2
    };

    options = {
      # General options
      updatetime = 100; # Faster completion
      hidden = true; # Keep closed buffer open in the background
      clipboard = "unnamed"; # Use system clipboard
      #mouse = "a"; # Enable mouse control
      mouse = ""; # Enable mouse control
      laststatus = 3; # When to use a status line for the last window
      fileencoding = "utf-8"; # File-content encoding for the current buffer
      termguicolors = true; # Enables 24-bit RGB color in the |TUI|

      # Timing
      timeoutlen = 1000;      # Wait time for a mapped sequence to complete


      # Line numbering options
      relativenumber = true; # Relative line numbers
      number = true; # Display the absolute line number of the current line

      # Search options
      incsearch = true; # Incremental search: show match for partly typed search command
      hlsearch = true; # Highlight search results.
      ignorecase = true; # When the search query is lower-case, match both lower and upper-case patterns
      smartcase = true; # Override the 'ignorecase' option if the search pattern contains uppercase characters
      #completeopt = [         # Set options for autocompletion.
      #  "menuone"             # Show popup menu even when there's only one match.
      #  "noselect"            # Do not preselect the first match in the completion menu.
      #];


      # Scrolling and cursor options
      scrolloff = 5; # Number of screen lines to show around the cursor
      cursorline = false; # Highlight the screen line of the cursor
      cursorcolumn = false; # Highlight the screen column of the cursor

      # Status and Display options
      splitbelow = true; # A new window is put below the current one
      splitright = true; # A new window is put right of the current one
      signcolumn = "yes"; # Whether to show the signcolumn
      colorcolumn = "100"; # Columns to highlight
      modeline = true; # Tags such as 'vim:ft=sh'
      modelines = 100; # Sets the type of modelines
      showmode = false; # disable showing the mode at the bottom of the screen
      showtabline = 2; # set the tabline to be always visible
      pumheight = 10; # set the height of the pop-up menu
      cmdheight = 2; # set the height of the command-line
      conceallevel = 0; # disable text concealment
      wrap = false; # disable line wrapping

      # Undo and swap options
      swapfile = false; # Disable the swap file
      undofile = true; # Automatically save and restore undo history

      # Spelling options
      spell = false; # Highlight spelling mistakes (local to window)

      # Tab options
      tabstop = 2; # Number of spaces a <Tab> in the text stands for (local to buffer)
      shiftwidth = 2; # Number of spaces used for each step of (auto)indent (local to buffer)
      softtabstop = 0; # If non-zero, number of spaces to insert for a <Tab> (local to buffer)
      expandtab = true; # Expand <Tab> to spaces in Insert mode (local to buffer)
      autoindent = true; # Do clever autoindenting
      cinkeys = ''-=0#''; # Dont delete comment indents

      # Folding options
      foldlevel = 99; # Folds with a level higher than this number will be closed

      # Text formatting options
      textwidth = 0; # Maximum width of text that is being inserted.  A longer line will be broken after white space to get this width.
    };
  };
}
