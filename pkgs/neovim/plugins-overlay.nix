{
  vimUtils,
  fetchFromGitHub,
}:
{
  overlay = self: super: {
    window-manager = vimUtils.buildVimPlugin {
      pname = "windowServer";
      version = "0.1.0";
      src = ./window-server;
    };

    smart-paste-nvim = import ./plugins/smart-paste/package.nix {
      inherit vimUtils fetchFromGitHub;
    };

    # rhizome builds its own Vim plugin as `passthru.plugin`, so it is pulled in
    # whole rather than as a bare plugin derivation.
    rhizome = import ../rhizome {
      inherit (super) lib;
      pkgs = super;
    };
  };

  # Export the nixvim modules for use in configurations
  modules = {
    smart-paste = ./plugins/smart-paste/module.nix;
    rhizome = ./plugins/rhizome/module.nix;
  };
}
