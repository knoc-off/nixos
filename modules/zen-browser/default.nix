{
  inputs,
  self,
  ...
}:
let
  inherit (self.lib.keyLayers) presets;

  # Drives both the home-manager module import and the package attribute name,
  # so switching channels is a one-line change.
  variant = "beta";
in
{

  home =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      addons = inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system};
    in
    {
      imports = [
        inputs.zen-browser.homeModules.${variant}
        (import ./fx-autoconfig.nix { inherit inputs variant; })
      ];

      programs.zen-browser = {
        enable = true;
        setAsDefaultBrowser = false;

        profiles.main = {
          id = 0;
          isDefault = true;

          settings = {
            # The only pref that has to be set by hand -- the loader's own prefs
            # ship in the package. Required for userChrome.css and for
            # fx-autoconfig's CSS namespaces.
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

            # Without these the Browser Console (Ctrl+Shift+J) displays output
            # but refuses to accept input, which makes debugging chrome scripts
            # needlessly painful.
            "devtools.chrome.enabled" = true;
            "devtools.debugger.remote-enabled" = true;

            # Keep the sidebar in its collapsed (narrow) state at rest. The
            # vendored expand-on-hover mod (styles/sidebery-collapse.css) then
            # reveals #navigator-toolbox on :hover; it is meaningless if the
            # sidebar is already expanded. Zen's own expand/collapse toggle
            # (ZenUIManager.mjs toggleExpand()) still flips this at runtime; it
            # resets to collapsed on restart.
            "zen.view.sidebar-expanded" = false;

            # Settings for the vendored StormAnon "Sidebar Expand on Hover" mod
            # (styles/sidebery-collapse.css). Zen's mod store would normally set
            # these; we supply them here since the mod is vendored. The mod's
            # CSS reads them via @media (-moz-pref / -moz-bool-pref ...). Values
            # are the mod's own defaults (from its preferences.json); the two
            # width tunables are supplied as CSS variables in the stylesheet's
            # :root block instead (collapsed 60px / expanded 300px).
            "mod.autoexpand.performance_mode" = "balanced";
            "mod.autoexpand.hide_workspace_indicator" = true;
            "mod.autoexpand.fade_sleeping_tabs" = true;
            "mod.autoexpand.fade_sleeping_folders" = true;
            "mod.autoexpand.essentials_vertical" = false;
            "mod.autoexpand.remove_line_separator" = false;

            # Uncomment if a script touches gBrowser or gURLBar at window
            # creation and the loader reports that startup was broken.
            # "userChromeJS.gBrowser_hack.enabled" = true;
          };

          # The integration script looks up the running Sidebery WebExtension by
          # name, so Sidebery has to be installed in this profile for it to do
          # anything -- otherwise it shows an "install Sidebery" spotlight.
          extensions = {
            force = true;
            packages = [ addons.sidebery ];
            # One-shot seed -- Firefox migrates extension storage to IndexedDB
            # on first read and never rereads storage.js after that. See
            # sidebery-settings.nix for the re-seed procedure.
            settings."{3c078156-979c-498b-8990-85f7987dd929}".settings = import ./sidebery-settings.nix;
          };

          userScripts = {
            "sidebery-integration.uc.js" = ./scripts/sidebery-integration.uc.js;
            # TEMPORARY -- loopback eval socket used to inspect the Sidebery
            # frame's live state. Remove this line and the script once the
            # sidebar collapse work is finished. See the file's header comment.
            "debug-bridge.uc.js" = ./scripts/debug-bridge.uc.js;
          };

          userStyles = {
            "sidebery.css" = ./styles/sidebery.css;
          };

          # Chrome-level CSS (targets #navigator-toolbox in browser.xhtml, not
          # a document inside the Sidebery frame), so this goes through
          # userChrome rather than fx-autoconfig's userStyles namespace.
          userChrome = ./styles/sidebery-collapse.css;
        };
      };

      keyLayers.layers.browser = lib.mkIf config.keyLayers.enable {
        classes = [
          "firefox"
          "chromium-browser"
        ];
        capsbinds = {
          ctrl = presets.appCtrlKeys;
          keys = presets.navKeys // {
            g = presets.docNavG;
          };
        };
      };

    };

}
