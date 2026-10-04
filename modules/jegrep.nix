{ self, ... }:
{
  nixos =
    { config, pkgs, ... }:
    let
      jegrep = self.packages.${pkgs.stdenv.hostPlatform.system}.jegrep;
      secret = config.sops.secrets."jev/api-key";
    in
    {
      sops.secrets."jev/api-key" = {
        sopsFile = ./shared-secrets.yaml;
        group = "users";
        mode = "0440";
      };

      # Jev key is a TypeSafe key; read at runtime so it never hits the store.
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "jegrep" ''
          TYPESAFE_API_KEY="$(< ${secret.path})" exec ${jegrep}/bin/jegrep "$@"
        '')
      ];
    };
}
