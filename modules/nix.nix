{ inputs, self, ... }: {
  nixos = { ... }: {
    nixpkgs.config.allowUnfree = true;
    # Local builders (mkComplgenScript, writeLuaScript, writeNuScript) as
    # pkgs.* on the host's own pkgs instance -- the same instance home-manager
    # sees, since every user profile sets useGlobalPkgs = true. This is
    # additive only: it does not touch self.packages' fenix/upkgs overlays,
    # which nothing at the host level depends on.
    nixpkgs.overlays = [ self.overlays.builders ];

    # Pre-size the Boehm GC heap for Nix evaluation. A full system eval grows the
    # heap to ~4.3GB and triggers 2 GC cycles; starting at 6GB avoids one of them
    # (~5-10% faster eval). Untouched pages cost no physical RAM (demand-paged),
    # so small nix commands are unaffected.
    environment.variables.GC_INITIAL_HEAP_SIZE = "6442450944"; # 6 GiB

    nix = {
      registry = {
        nixpkgs.flake = inputs.nixpkgs;
        nixos-hardware.flake = inputs.hardware;
      };
      #nix.nixPath = [ "/etc/nix/path" ];
      #environment.etc."nix/path/nixpkgs".source = inputs.nixpkgs;
      nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
      settings = {
        extra-substituters = [
          "https://hyprland.cachix.org"
        ];
        extra-trusted-public-keys = [
          "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        ];
        experimental-features = [
          "nix-command"
          "flakes"
          "pipe-operators"
        ];
        trusted-users = [ "@wheel" ];
        download-buffer-size = 4294967296; # 4gb # 2147483648; # 2GB
      };
    };
  };
}
