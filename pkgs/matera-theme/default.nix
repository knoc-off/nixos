{ bc, cantarell-fonts, fetchFromGitHub, lib, makeFontsConf, optipng, resvg
, runCommandLocal, sassc, stdenv

# A base16 theme configuration as defined in the `theme.dark.base16` module.
, configBase16 ? {
  name = "Replace-Me";
  kind = "dark";
  colors = {
    base00 = "000000";
    base01 = "000000";
    base02 = "000000";
    base03 = "000000";
    base04 = "000000";
    base05 = "000000";
    base06 = "000000";
    base07 = "000000";
    base08 = "000000";
    base09 = "000000";
    base0A = "000000";
    base0B = "000000";
    base0C = "000000";
    base0D = "000000";
    base0E = "000000";
    base0F = "000000";
  };
} }:

let

  version = "20210322";

in stdenv.mkDerivation {
  pname = "materia-theme";
  inherit version;

  src = fetchFromGitHub {
    owner = "nana-4";
    repo = "materia-theme";
    rev = "v${version}";
    sha256 = "1fsicmcni70jkl4jb3fvh7yv0v9jhb8nwjzdq8vfwn256qyk0xvl";
  };

  nativeBuildInputs = [
    bc
    optipng
    sassc

    (runCommandLocal "rendersvg" { } ''
      mkdir -p $out/bin
      ln -s ${resvg}/bin/resvg $out/bin/rendersvg
    '')
  ];

  dontConfigure = true;

  # Fixes problem "Fontconfig error: Cannot load default config file"
  FONTCONFIG_FILE = makeFontsConf { fontDirectories = [ cantarell-fonts ]; };

  theme = let inherit (configBase16) colors;
  in lib.generators.toKeyValue { } {
    # Color selection copied from
    # https://github.com/pinpox/nixos-home/blob/1cefe28c72930a0aed41c20d254ad4d193a3fa37/gtk.nix#L11
    ACCENT_BG = colors.base0B;
    ACCENT_FG = colors.base00;
    BG = colors.base00;
    BTN_BG = colors.base02;
    BTN_FG = colors.base06;
    FG = colors.base05;
    HDR_BG = colors.base02;
    HDR_BTN_BG = colors.base01;
    HDR_BTN_FG = colors.base05;
    HDR_FG = colors.base05;
    MATERIA_SURFACE = colors.base02;
    MATERIA_VIEW = colors.base01;
    MENU_BG = colors.base02;
    MENU_FG = colors.base06;
    SEL_BG = colors.base0D;
    SEL_FG = colors.base0E;
    TXT_BG = colors.base02;
    TXT_FG = colors.base06;
    WM_BORDER_FOCUS = colors.base05;
    WM_BORDER_UNFOCUS = colors.base03;

    MATERIA_COLOR_VARIANT = configBase16.kind;
    MATERIA_STYLE_COMPACT = "True";
    UNITY_DEFAULT_LAUNCHER_STYLE = "False";
  };

  passAsFile = [ "theme" ];

  postPatch = ''
    patchShebangs .

    sed -e '/handle-horz-.*/d' -e '/handle-vert-.*/d' \
      -i ./src/gtk-2.0/assets.txt
  '';

  buildPhase = ''
    export HOME="$NIX_BUILD_ROOT"
    ./change_color.sh \
       -i False \
       -t $out/share/themes \
       -o ${configBase16.name} \
       "$themePath"
  '';
}

