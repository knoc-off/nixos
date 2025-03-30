{ pkgs, self, lib, ... }:
let
  renamedMinimal = pkgs.symlinkJoin {
    name = "nvim-minimal";
    paths = [ self.packages.${pkgs.system}.neovim-nix.minimal ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      # Wrap the nvim binary as nvim-minimal.
      wrapProgram $out/bin/nvim \
        --prefix PATH : ${self.packages.${pkgs.system}.neovim-nix.minimal}/bin \
        --set NAME nvim-minimal
      mv $out/bin/nvim $out/bin/nvim-minimal

      # Remove any other binaries in $out/bin.
      for bin in $out/bin/*; do
        base=$(basename "$bin")
        if [ "$base" != "nvim-minimal" ]; then
          rm -f "$bin"
        fi
      done
    '';
  };
in {
  home.packages = [
    self.packages.${pkgs.system}.neovim-nix.default
    renamedMinimal

  ];
  #home.packages = [  ];
  home.sessionVariables = { EDITOR = lib.mkForce "nvim"; };

  xdg.desktopEntries = {
    kitty-neovim = {
      name = "Kitty Neovim";
      genericName = "Text Editor";
      exec =
        "kitty --detach nvim %U"; # this "nvim" can be replace by an explicit link to a binary
      icon = "${pkgs.neovim}/share/icons/hicolor/128x128/apps/nvim.png";
      terminal = false;
      categories = [ "Application" "Development" "IDE" ];
      mimeType = [ "text/plain" ];
    };
  };
}
