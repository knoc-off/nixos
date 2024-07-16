{inputs, ...}: {
  nix = {
    #nix.nixPath = [ "/etc/nix/path" ];
    #environment.etc."nix/path/nixpkgs".source = inputs.nixpkgs;
    nixPath = ["nixpkgs=${inputs.nixpkgs}"];
    settings = {
      substituters = ["https://hyprland.cachix.org"];
      trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
      experimental-features = ["nix-command" "flakes"];
      trusted-users = ["@wheel"];
    };
  };
}
