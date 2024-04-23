{ ...}:
{



  nixpkgs.overlays = [(self: super: {
    octoprint = super.octoprint.override {
      packageOverrides = pyself: pysuper: {
        BedLevelVisualizer = pyself.buildPythonPackage rec {
          pname = "BedLevelVisualizer";
          version = "1.1.1";
          src = self.fetchFromGitHub {
            owner = "jneilliii";
            repo = "OctoPrint-BedLevelVisualizer";
            rev = "${version}";
            sha256 = "sha256-6JcYvYgEmphp5zz4xZi4G0yTo4FCIR6Yh+MXYK7H7+w=";
          };
          propagatedBuildInputs = [ pysuper.octoprint ];
          doCheck = false;
        };
        OctoPrint-FirmwareUpdater = pyself.buildPythonPackage rec {
          pname = "FirmwareUpdater";
          version = "1.14.0";
          src = self.fetchFromGitHub {
            owner = "OctoPrint";
            repo = "OctoPrint-FirmwareUpdater";
            rev = "${version}";
            sha256 = "sha256-CUNjM/IJJS/lqccZ2B0mDOzv3k8AgmDreA/X9wNJ7iY=";
          };
          propagatedBuildInputs = [ pysuper.octoprint ];
          doCheck = false;
        };
        octoprint-prettygcode = pyself.buildPythonPackage rec {
          pname = "PrettyGCode";
          version = "1.2.4";
          src = self.fetchFromGitHub {
            owner = "Kragrathea";
            repo = "OctoPrint-PrettyGCode";
            rev = "v${version}";
            sha256 = "sha256-q/B2oEy+D6L66HqmMkvKfboN+z3jhTQZqt86WVhC2vQ=";
          };
          propagatedBuildInputs = [ pysuper.octoprint ];
          doCheck = false;
        };
      };
    };
  })];


  services.octoprint = {
    enable = true;
    port = 8080;
    openFirewall = true;
    plugins = plugins: with plugins; [
      themeify
      #stlviewer
      #octoprint-prettygcode
      BedLevelVisualizer
      #OctoPrint-FirmwareUpdater
    ];

    user = "octoprint";

  };


  # octoprint user groups. needs video
  users.users.octoprint = {
    extraGroups = [ "video" ];
  };
}

