# NixOS, home-manager, system configuration, package installation, program enablement, system options.
{
  outputs,
  self,
  pkgs,
  upkgs,
  user,
  inputs,
  system,
  color-lib,
  theme,
  ...
}: {
  #imports = [ inputs.ags.homeManagerModules.default ];

  home.packages = [
    inputs.astal.packages.${system}.default
    # inputs.astal.packages.${system}.gjs
    #inputs.ags.packages.${system}.default

    (inputs.ags.packages.${system}.default.override {
      extraPackages = with inputs.astal.packages.${system}; [
        notifd
        mpris
        network
        battery
        bluetooth
        powerprofiles
        tray
      ];
    })

    (self.packages.${pkgs.stdenv.hostPlatform.system}.astal-widget-wrapper {
      path = ./configs/notifications;
      entry = "app.tsx";
      name = "astal-notify";
    })
  ];
}
# this is a bit of a nightmare, but it might be worth doing...
#     (pkgs.stdenvNoCC.mkDerivation rec {
#       name = "astal-notifications";
#       src =
#         ./configs/notifications; # Your application's source directory (e.g., app.tsx)
#
#       # Dependencies needed during the build and for creating the wrapper script
#       nativeBuildInputs = [
#         inputs.ags.packages.${system}.default # Provides the 'ags' binary for bundling
#         pkgs.wrapGAppsHook # Essential for setting up GNOME/GObject runtime environment
#         pkgs.makeWrapper # For creating the final executable script
#         pkgs.nodejs # AGS might use Node.js internally for its bundling process
#         pkgs.typescript # For TypeScript compilation, if 'ags bundle' relies on 'tsc'
#       ];
#
#       # Runtime dependencies that your bundled application and GJS will need
#       buildInputs = with inputs.astal.packages.${system}; [
#         astal3 # Main Astal library
#         astal4 # Main Astal library
#         io # Astal I/O utilities
#         notifd # Notification daemon integration
#         mpris # Media player information
#         network # Network status
#         battery # Battery information
#         bluetooth # Bluetooth interaction
#         powerprofiles # Power profile management
#         tray # System tray icons
#
#         # Core GObject libraries
#         pkgs.gjs
#         pkgs.glib
#         pkgs.gobject-introspection
#         pkgs.gtk3
#         pkgs.gtk4
#         pkgs.libadwaita
#
#
#         pkgs.gjs # The GJS interpreter itself
#         pkgs.glib # Explicitly include GLib for version consistency
#         # Override gvfs to ensure it's linked against *our* specific pkgs.glib version.
#         # This is critical for resolving the 'undefined symbol: g_variant_builder_init_static' error.
#         pkgs.gvfs
#         pkgs.gsettings-desktop-schemas # For GSettings schemas (required for XDG_DATA_DIRS)
#
#         # The 'gjs' output from AGS contains the Astal GJS runtime environment
#         inputs.ags.packages.${system}.gjs
#       ];
#
#       buildPhase = ''
#         export HOME=$TMPDIR
#         export PATH="${
#           lib.makeBinPath [
#             pkgs.nodejs
#             pkgs.typescript
#             inputs.ags.packages.${system}.default
#           ]
#         }:$PATH"
#
#         echo "--- Running ags bundle with ES module output ---"
#         # Try to force ES module output with .mjs extension
#         ags bundle --format esm app.tsx bundled-app.mjs || \
#         ags bundle --es-module app.tsx bundled-app.mjs || \
#         ags bundle app.tsx bundled-app.mjs
#
#         # If .mjs wasn't created, try .js
#         if [ ! -f "bundled-app.mjs" ] && [ -f "bundled-app.js" ]; then
#           mv bundled-app.js bundled-app.mjs
#         fi
#
#         # Verify we have output
#         if [ ! -f "bundled-app.mjs" ]; then
#           echo "Error: No bundled output found"
#           exit 1
#         fi
#
#         echo "--- Bundling complete ---"
#       '';
#
#       installPhase = ''
#         mkdir -p $out/share/${name}
#
#         # Copy the ES module
#         cp bundled-app.mjs $out/share/${name}/app.mjs
#         cp -r ./* $out/share/${name}/ || true
#
#         mkdir -p $out/bin
#
#         echo "--- Creating executable wrapper with proper typelib paths ---"
#         makeWrapper ${pkgs.gjs}/bin/gjs $out/bin/${name} \
#           --add-flags "--module" \
#           --add-flags "$out/share/${name}/app.mjs" \
#           --prefix GJS_PATH : "${
#             inputs.ags.packages.${system}.gjs
#           }/share/astal/gjs" \
#           --prefix GI_TYPELIB_PATH : "${pkgs.glib}/lib/girepository-1.0" \
#           --prefix GI_TYPELIB_PATH : "${pkgs.gtk3}/lib/girepository-1.0" \
#           --prefix GI_TYPELIB_PATH : "${pkgs.gtk4}/lib/girepository-1.0" \
#           --prefix GI_TYPELIB_PATH : "${pkgs.libadwaita}/lib/girepository-1.0" \
#           --prefix GI_TYPELIB_PATH : "${pkgs.gobject-introspection}/lib/girepository-1.0" \
#           --prefix GI_TYPELIB_PATH : "${
#             lib.makeSearchPath "lib/girepository-1.0" buildInputs
#           }" \
#           --prefix GIO_MODULE_PATH : "${pkgs.gvfs}/lib/gio/modules" \
#           --prefix XDG_DATA_DIRS : "$out/share:${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}" \
#           --prefix PATH : "${
#             lib.makeBinPath [ inputs.astal.packages.${system}.io ]
#           }" \
#           --argv0 "$name"
#       '';
#
#       # preFixup is a special phase run *just before* 'wrapGAppsHook'.
#       # This allows us to influence the environment variables that 'wrapGAppsHook' sets
#       # for the final executable. This is crucial for fixing the GLib/GVFS issue.
#       preFixup = ''
#         echo "--- Applying gappsWrapperArgs in preFixup ---"
#         # Add GLib's library path to LD_LIBRARY_PATH. This ensures that the dynamic
#         # linker finds the correct GLib version at runtime for all shared libraries,
#         # specifically addressing the GVFS symbol resolution problem.
#         gappsWrapperArgs+=(
#           --prefix LD_LIBRARY_PATH : "${pkgs.glib}/lib"
#           # These flags can sometimes help with subtle GIO/GVFS module loading issues
#           --unset GVFS_DISABLE_FUSE
#           --set GLIB_NETWORKING_USE_PKCS11 0
#         )
#         echo "--- gappsWrapperArgs applied ---"
#       '';
#
#       meta = {
#         description = "Astal-based notification daemon wrapped for NixOS";
#         platforms = lib.platforms.linux;
#       };
#     })

