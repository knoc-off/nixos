{ lib
, python3
, fetchFromGitHub
}:

python3.pkgs.buildPythonApplication rec {
  pname = "vim-ai-replicate-bridge";
  version = "0.1.0";

  src = ./.;

  propagatedBuildInputs = with python3.pkgs; [
    flask
    replicate
    #(pkgs.python312Packages.replicate)
  ];

  #buildInputs = [ setuptools pip ];

  #postInstall = ''
  #  mkdir -p $out/bin
  #  cp vim_ai_replicate_bridge.py $out/bin/vim_ai_replicate_bridge
  #  chmod +x $out/bin/vim_ai_replicate_bridge
  #'';

}
