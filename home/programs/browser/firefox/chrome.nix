{ pkgs, lib }:
{ firefox-csshacks }:

let
  # Create a proper derivation from a CSS file
  mkModule = name: cssFile: pkgs.stdenv.mkDerivation {
    pname = "firefox-chrome-${name}";
    version = "0.1.0";
    src = cssFile;

    dontUnpack = true;

    installPhase = ''
      cp $src $out
    '';
  };

  # Get all CSS files from firefox-csshacks/chrome/
  chromeFiles = builtins.readDir "${firefox-csshacks}/chrome";

  # Filter to only .css files
  cssFiles = lib.filterAttrs (name: type:
    type == "regular" && lib.hasSuffix ".css" name
  ) chromeFiles;

  # Convert filename to module name (remove .css)
  toModuleName = name: lib.removeSuffix ".css" name;

  # Create attrset of derivations
  modules = lib.mapAttrs' (filename: _:
    let
      moduleName = toModuleName filename;
      cssPath = "${firefox-csshacks}/chrome/${filename}";
    in
      lib.nameValuePair moduleName (mkModule moduleName cssPath)
  ) cssFiles;

in modules // {
  # Helper to create a custom CSS module
  mkCustom = css: pkgs.writeText "custom-chrome.css" css;

  # Helper to compose modules into userChrome string
  mkUserChrome = moduleList: ''
    ${lib.concatMapStrings (mod: "@import \"${mod}\";\n") moduleList}
  '';
}
