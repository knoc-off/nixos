{
  vimUtils,
  lua,
  fetchFromGitHub,
}: {
  overlay = self: super: {
    window-manager = vimUtils.buildVimPlugin {
      pname = "windowServer";
      version = "0.1.0";
      src = ./window-server;
    };

    smart-paste-nvim = import ../neovim/plugins/smart-paste/package.nix {
      inherit vimUtils fetchFromGitHub;
    };
  };

  # Export the smart-paste nixvim module for use in configurations
  modules = {
    smart-paste = ../neovim/plugins/smart-paste/module.nix;
  };
}

