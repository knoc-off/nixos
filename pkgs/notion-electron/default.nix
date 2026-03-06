{
  appimageTools,
  fetchurl,
}:
let
  pname = "notion-electron";
  version = "1.9.5";

  src = fetchurl {
    url = "https://github.com/anechunaev/notion-electron/releases/download/v${version}/Notion_Electron-${version}-x86_64.AppImage";
    sha256 = "0r3slp3hpkci75lq72krnvin64lap92wibf7zv50gq46dyifqrv6";
  };

  appimageContents = appimageTools.extractType2 {inherit pname version src;};
in
  appimageTools.wrapType2 {
    inherit pname version src;

    extraInstallCommands = ''
      install -Dm444 ${appimageContents}/notion-electron.desktop $out/share/applications/notion-electron.desktop
      substituteInPlace $out/share/applications/notion-electron.desktop \
        --replace-fail 'Exec=AppRun' 'Exec=${pname}'
      cp -r ${appimageContents}/usr/share/icons $out/share/icons
    '';

    meta = {
      description = "Unofficial Notion desktop client for Linux";
      homepage = "https://github.com/anechunaev/notion-electron";
      license.spdxId = "MIT";
      platforms = ["x86_64-linux"];
    };
  }
