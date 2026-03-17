{
  pkgs,
  lib,
  osConfig ? {},
  ...
}: let
  # All sops secrets prefixed with "shell_environment/" are automatically
  # exported as session variables. The prefix is stripped from the var name.
  # To add a new one, just declare it in your system config:
  #   sops.secrets."shell_environment/MY_API_KEY" = {};
  sopsSecrets = lib.attrByPath ["sops" "secrets"] {} osConfig;

  shellSecrets = lib.filterAttrs (name: _: lib.hasPrefix "shell_environment/" name) sopsSecrets;

  secretSessionVars = lib.mapAttrs' (name: secret: {
    name = lib.removePrefix "shell_environment/" name;
    value = "$(cat ${secret.path})";
  }) shellSecrets;
in {
  imports = [
    ./scripts.nix
  ];

  home.packages = with pkgs; [
    chroma
    qrencode
    fd
    fzf
    ripgrep
    pigz
    pv
    sourceHighlight
    zoxide
  ];

  home.sessionVariables = secretSessionVars;
}
