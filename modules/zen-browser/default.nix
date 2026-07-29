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
          };

          userStyles = {
            "sidebery.css" = ./styles/sidebery.css;
          };
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
