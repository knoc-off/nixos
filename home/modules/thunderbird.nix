{ lib, pkgs, config, ... }:
with lib;
let
  # Shorter name to access final settings a
  # user of hello.nix module HAS ACTUALLY SET.
  # cfg is a typical convention.
  cfg = config.services.emailManager;
in
{
  # Declare what settings a user of this "hello.nix" module CAN SET.
  options.services.emailManager = {
    enable = mkEnableOption "Thunderbird service";
    profile = mkOption {
      type = types.str;
      default = "default";
    };
  };

  # Define what other settings, services and resources should be active IF
  # a user of this "hello.nix" module ENABLED this module
  # by setting "services.hello.enable = true;".
  config = mkIf cfg.enable {
    programs.thunderbird = {
      enable = true;
      #greeter = cfg.greeter;
      profiles.${cfg.profile} = {
        isDefault = true;
        #name = lib.mkdefault "${cfg.profile}-profile";

        # user.js
        settings = { };

        # user js
        extraConfig = ''
        '';

        # look of the app
        userChrome = ''
        '';

        # look of the content
        userContent = ''
        '';

      };
    };
  };
}
