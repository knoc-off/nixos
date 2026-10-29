{ ... }: {
  home =
    { config, pkgs, lib, ... }:
    let
      # One entry per handler: the package that ships the .desktop file, the
      # file's name, and the MIME types it should be the default for. Both the
      # mimeApps table and the existence check below are generated from this,
      # so a handler that is no longer installed (Evince, qview, ...) fails the
      # build instead of silently leaving dangling defaults.
      apps = {
        feh = {
          pkg = pkgs.feh;
          desktop = "feh.desktop";
          mimes = map (t: "image/${t}") [
            "bmp"
            "gif"
            "jpeg"
            "jpg"
            "png"
            "tiff"
            "webp"
            "heic"
            "svg+xml"
            "x-tga"
            "x-pcx"
            "x-xbitmap"
            "x-portable-anymap"
            "x-portable-bitmap"
            "x-portable-graymap"
            "x-portable-pixmap"
          ];
        };

        f3d = {
          pkg = pkgs.f3d;
          desktop = "f3d.desktop";
          # f3d also claims image/png|jpeg|bmp; deliberately left to feh.
          mimes =
            map (t: "model/${t}") [
              "stl"
              "obj"
              "3mf"
              "gltf+json"
              "gltf-binary"
              "vrml"
              "iges"
              "vnd.usda"
              "vnd.usdz+zip"
            ]
            ++ map (t: "application/vnd.${t}") [
              "step"
              "brep"
              "fbx"
              "dae"
              "ply"
              "3ds"
              "usd"
              "usdc"
              "vtk"
              "vtp"
              "vtu"
            ]
            ++ [ "image/vnd.dxf" ];
        };

        mpv = {
          pkg = config.programs.mpv.package;
          desktop = "mpv.desktop";
          mimes =
            map (t: "video/${t}") [
              "mp4"
              "webm"
              "x-matroska"
              "mpeg"
              "quicktime"
              "x-msvideo"
              "x-m4v"
              "x-flv"
              "ogg"
              "3gpp"
            ]
            ++ map (t: "audio/${t}") [
              "mpeg"
              "mp4"
              "ogg"
              "flac"
              "wav"
              "x-wav"
              "aac"
              "x-m4a"
              "opus"
              "x-ms-wma"
              "webm"
            ];
        };

        firefox = {
          pkg = config.programs.firefox.finalPackage;
          desktop = "firefox.desktop";
          mimes = [
            "application/pdf"
            "text/html"
            "application/xhtml+xml"
            "x-scheme-handler/http"
            "x-scheme-handler/https"
          ];
        };

        file-roller = {
          pkg = pkgs.file-roller;
          desktop = "org.gnome.FileRoller.desktop";
          mimes = map (t: "application/${t}") [
            "zip"
            "gzip"
            "x-gzip"
            "bzip2"
            "x-bzip2"
            "x-tar"
            "x-compressed-tar"
            "x-bzip-compressed-tar"
            "x-xz"
            "x-xz-compressed-tar"
            "zstd"
            "x-7z-compressed"
            "vnd.rar"
            "x-rar"
            "x-iso9660-image"
            "x-cd-image"
            "java-archive"
            "vnd.debian.binary-package"
          ];
        };

        nautilus = {
          pkg = pkgs.nautilus;
          desktop = "org.gnome.Nautilus.desktop";
          mimes = [ "inode/directory" ];
        };
      };

      # term-neovim.desktop is declared by modules/editor.nix (an
      # xdg.desktopEntries entry, not a package), so it is asserted on below
      # rather than checked in the store.
      textMimes =
        map (t: "text/${t}") [
          "plain"
          "markdown"
          "csv"
          "x-log"
          "x-nix"
          "x-rust"
          "x-go"
          "x-c"
          "x-c++"
          "x-csrc"
          "x-chdr"
          "x-lua"
          "x-makefile"
          "x-cmake"
          "x-diff"
          "x-patch"
          "x-tex"
          "x-readme"
          "x-ini"
          "toml"
        ]
        ++ map (t: "application/${t}") [
          "json"
          "xml"
          "toml"
          "yaml"
          "x-yaml"
          "x-shellscript"
          "x-perl"
          "x-python"
          "x-ruby"
          "x-php"
          "x-java"
          "x-javascript"
          "javascript"
          "sql"
          "x-sql"
        ];

      defaultsFor = desktop: mimes: lib.genAttrs mimes (_: [ desktop ]);

      handlersExist = pkgs.runCommand "xdg-mime-handlers-exist" { } ''
        ${lib.concatMapStringsSep "\n" (
          a: ''test -f ${a.pkg}/share/applications/${a.desktop} || { echo "modules/xdg.nix: ${a.desktop} not shipped by ${a.pkg}"; exit 1; }''
        ) (lib.attrValues apps)}
        mkdir $out
      '';
    in
    {
      assertions = [
        {
          assertion = config.xdg.desktopEntries ? term-neovim;
          message = "modules/xdg.nix: term-neovim.desktop comes from modules/editor.nix; import self.homeModules.editor";
        }
      ];

      # gnome settings app
      xdg.desktopEntries."org.gnome.Settings" = {
        name = "Settings";
        comment = "Gnome Control Center";
        icon = "org.gnome.Settings";
        exec = "env XDG_CURRENT_DESKTOP=gnome ${pkgs.gnome-control-center}/bin/gnome-control-center";
        categories = [ "X-Preferences" ];
        terminal = false;
      };

      programs.mpv.enable = true;

      home.packages = [
        handlersExist
        pkgs.gnome-disk-utility
        # Nautilus + supporting bits: file-roller handles archive extraction
        # from the right-click menu, sushi provides space-bar quick preview.
        pkgs.sushi
      ]
      ++ map (a: a.pkg) (lib.attrValues (lib.removeAttrs apps [ "mpv" "firefox" ]));

      xdg.mimeApps = {
        enable = true;
        defaultApplications =
          lib.foldl' (acc: a: acc // defaultsFor a.desktop a.mimes) { } (lib.attrValues apps)
          // defaultsFor "term-neovim.desktop" textMimes
          // {
            "x-scheme-handler/spotify" = [ "spotify.desktop" ];
          };
      };
    };
}
