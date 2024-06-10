{ lib
, fetchFromGitHub
, pkgs
}:

pkgs.stdenv.mkDerivation rec {
  pname = "mcscript";
  version = "0.2.3";

  src = fetchFromGitHub {
    owner = "Stevertus";
    repo = "mcscript";
    rev = version;
    hash = "sha256-+eC+UtJhnBao5nsytRROW+s4K3E1hG+n8QJpkN8ZaH8=";
  };

  buildInputs = [
    pkgs.nodejs
    pkgs.nodePackages.npm
  ];

  installPhase = ''
    # Create directories
    mkdir -p $out/bin
    mkdir -p $out/lib

    # Copy source files
    cp -r * $out

    # Install npm dependencies
    pushd $out
    npm install
    popd

    # Create a wrapper script
    cat > $out/bin/mcscript <<EOF
#!/bin/sh
exec ${pkgs.nodejs}/bin/npx mcscript "\$@"
EOF

    chmod +x $out/bin/mcscript
  '';

  meta = with lib; {
    description = "A programming language for Minecraft Vanilla";
    homepage = "https://github.com/Stevertus/mcscript";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    platforms = platforms.all;
  };
}
