{pkgs, config, libs, ...}:
{
  programs.ssh = {
    matchBlocks = {
      "nixprod" = {
        hostname = "167.235.233.71";
        port = 22;
        user = "root";
        identityFile = [
          "~/.ssh/id_rsa"
        ];
      };
      "kobbl" = {
        hostname = "kobbl.co";
        port = 22;
        user = "root";
        identityFile = [
          "~/.ssh/id_rsa"
        ];
      };
    };
  };
}
