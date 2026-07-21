# insp-stitch: parallax-aware dual-fisheye stitcher for Insta360 X5 .insp photos.
{
  lib,
  stdenv,
  pkgs,
  python3,
  makeWrapper,
}: let
  py = python3.withPackages (ps:
    with ps; [
      opencv4
      numpy
      scipy
      numba
    ]);
in
  stdenv.mkDerivation {
    pname = "insp-stitch";
    version = "0.1.0";

    src = ./insp_stitch;

    dontBuild = true;

    nativeBuildInputs = [makeWrapper];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/insp-stitch/insp_stitch $out/bin
      cp -r . $out/lib/insp-stitch/insp_stitch

      makeWrapper ${py}/bin/python3 $out/bin/insp-stitch \
        --add-flags "-m insp_stitch" \
        --set PYTHONPATH "$out/lib/insp-stitch"

      makeWrapper ${py}/bin/python3 $out/bin/insp-stitch-flowlab \
        --add-flags "-m insp_stitch.flow_experiments" \
        --set PYTHONPATH "$out/lib/insp-stitch"

      runHook postInstall
    '';

    passthru.devShell = pkgs.mkShell {
      packages = [py pkgs.ffmpeg];
      shellHook = ''
        echo "insp-stitch dev shell"
        echo "  python -m insp_stitch <input.insp> -o stitched.jpg -w 7680"
        export PYTHONPATH="${toString ./.}:$PYTHONPATH"
      '';
    };

    meta = {
      description = "Parallax-aware dual-fisheye stitcher for Insta360 X5 .insp photos";
      longDescription = ''
        Stitches Insta360 X5 .insp dual-fisheye photos into equirectangular
        images. Auto-searches lens FOV/orientation to align the far field,
        then uses DIS optical flow at the seams to correct residual,
        depth-dependent parallax before a coverage-weighted blend.
      '';
      license = lib.licenses.mit;
      platforms = lib.platforms.all;
      mainProgram = "insp-stitch";
    };
  }
