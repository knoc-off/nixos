{pkgs ? import <nixpkgs> {}}:
pkgs.python3Packages.buildPythonApplication {
  pname = "volumeLerp";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    pkgs.makeWrapper
  ];

  postFixup = ''
    wrapProgram $out/bin/volumeLerp --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.alsaUtils]}
  '';

  makeWrapperArgs = [
    "--set"
    "PYTHONPATH"
    "$out/${pkgs.python3.sitePackages}:$PYTHONPATH"
  ];

  meta = with pkgs.lib; {
    description = "A script to smoothly change the volume using linear interpolation";
    homepage = "https://example.com";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    platforms = platforms.unix;
  };
}
