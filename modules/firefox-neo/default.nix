# firefox-neo: native Firefox with fx-autoconfig userscripts, Sidebery in the
# native sidebar, and a collapse-to-rail sidebar.
#
# Successor to modules/zen-browser. That setup reparented Sidebery's frame into
# Zen's tab strip by hand, which meant owning the frame's lifecycle -- including
# its browsing context group, whose mis-assignment silently broke every
# WebExtension IPC call on the first window. Here Sidebery loads in the sidebar
# Firefox already provides, so none of that machinery exists to go wrong.
#
# Deliberately separate from modules/firefox rather than folded into it: that
# module is in use by another user (niko/thinkpad-work) and its Sidebery
# settings differ. Running both side by side keeps this iterable without
# risking a working config. They use different profile directories.
{ inputs, self, ... }:
let
  inherit (self.lib) color-lib theme;

  neoTheme = import ./theme.nix { inherit theme color-lib; };
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

      firefox-neo = self.packages.${pkgs.stdenv.hostPlatform.system}.firefox-neo;
      fxAutoconfig = inputs.fx-autoconfig;

      # MrOtherGuy's csshacks, same source the firefox module uses.
      firefox-csshacks = pkgs.stdenv.mkDerivation {
        name = "firefox-csshacks-neo";
        src = inputs.firefox-csshacks;
        installPhase = "cp -r . $out";
      };

      profileName = "neo";
      configPath = ".mozilla/firefox-neo";
      profileDir = "${configPath}/${profileName}";

      # Userscripts and userstyles, installed into the profile below.
      chromeSrc = ./chrome;
    in
    {
      programs.firefox = {
        enable = true;
        package = firefox-neo;
        inherit configPath;

        profiles.${profileName} = {
          isDefault = true;
          id = 0;
          name = profileName;

          extensions = {
            force = true;
            packages = with addons; [
              sidebery
              ublock-origin
              bitwarden
              # Applies neoTheme.colorTheme through the official theme API.
              firefox-color
            ];
            settings = {
              "{3c078156-979c-498b-8990-85f7987dd929}" = {
                force = true;
                settings = import ./sidebery-settings.nix // {
                  # Sidebery's own custom-CSS setting, which it applies to the
                  # sidebar document itself.
                  #
                  # The Zen setup could not use this: it injected the sheet by
                  # hand via Extension:InitBrowser, because it was already
                  # building the panel's <browser> and could seed the stylesheet
                  # list at frame-init. Here the sidebar is Firefox's own, so
                  # there is no init to hook -- and sending InitBrowser to a
                  # *live* frame tears it down (verified: it killed the browser).
                  #
                  # Reading the file at eval time rather than pointing at a
                  # chrome:// URL: this value is stored in extension storage, so
                  # it has to be the CSS text, not a reference to it.
                  sidebarCSS = builtins.readFile ./chrome/CSS/sidebery.css;
                };
              };
              "FirefoxColor@mozilla.com" = {
                force = true;
                settings = neoTheme.colorTheme;
              };
            };
          };

          # neoTheme.userChrome defines the --lwt-*/--toolbar-* custom
          # properties Firefox's chrome reads, so it has to come first --
          # the imported sheets below consume those variables.
          #
          # autohide_sidebar supplies the hover machinery; sidebery-collapse.css
          # retargets it (60px rail, 300px expanded, Sidebery-scoped). Order
          # matters -- the override has to come second.
          #
          # @import must precede all other rules in a stylesheet, so the
          # imports lead and the variable block follows.
          userChrome = ''
            @import "${firefox-csshacks}/chrome/autohide_sidebar.css";
            @import "${chromeSrc}/CSS/sidebery-collapse.css";

            ${neoTheme.userChrome}
          '';

          # In-content pages (about:config, about:addons, about:preferences)
          # are styled by the design-token system, not by --lwt-*, so they need
          # their own sheet. Without this they keep Firefox 154's violet
          # "nova" accent regardless of what the chrome is themed to.
          userContent = neoTheme.userContent;

          settings = neoTheme.settings // {
            # Required for userChrome.css to be read at all.
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

            # Static layout is deliberately OFF.
            #
            # It holds #sidebar at the full 300px and animates a clipping
            # container instead, which is smoother -- but it means the frame's
            # viewport is ALWAYS 300px. Sidebery lays its panel out from
            # @media (max-width: ...) on its own viewport, so under static
            # layout the collapsed view never triggers: the rail just shows the
            # left 60px of the expanded layout, clipping the tab titles and
            # pushing the nav buttons out of sight.
            #
            # Measured with the bridge, the reason static layout existed does
            # not apply here: sampling across the transition, the remote frame
            # tracks the chrome width within 1px continuously (73/73, 144/145,
            # 243/243, 296/297). The one-jump late reflow that motivated it in
            # the Zen setup was a consequence of the hand-reparented frame
            # there, not of remote browsers generally.
            "userchrome.autohide-sidebar.static-layout.enabled" = false;

            # Sidebery replaces the tab strip; the horizontal one is redundant.
            "browser.tabs.inTitlebar" = 0;

            # Vertical tabs, which is what actually removes the horizontal tab
            # strip from the titlebar (inTitlebar=0 alone only unmerges it from
            # the window decorations). Firefox's own vertical strip is then
            # hidden in CSS -- see the #sidebar-container rule in
            # sidebery-collapse.css -- so Sidebery gets that space instead.
            #
            # Kept on rather than reverting to horizontal tabs because this is
            # also what moves the sidebar into the revamp layout that the
            # collapse CSS targets; sidebar.revamp is implied by verticalTabs
            # but set explicitly so the layout cannot silently change.
            "sidebar.verticalTabs" = true;
            "sidebar.revamp" = true;

            # The debug bridge needs chrome-level devtools access.
            "devtools.chrome.enabled" = true;
            "devtools.debugger.remote-enabled" = true;

            # Extensions here are sideloaded into the profile directory rather
            # than installed through AMO. Firefox's default autoDisableScopes
            # (15) parks every such discovery in "disabled, awaiting user
            # approval", and startupScanScopes (0) skips rescanning the
            # profile's extensions/ dir entirely. 0/1 installs them enabled.
            "extensions.autoDisableScopes" = 0;
            "extensions.startupScanScopes" = 1;

            # First-run experience: onboarding tour, "what's new" tab, import
            # wizard, default-browser nag.
            "browser.aboutwelcome.enabled" = false;
            "browser.startup.homepage_override.mstone" = "ignore";
            "browser.messaging-system.whatsNewPanel.enabled" = false;
            "trailhead.firstrun.didSeeAboutWelcome" = true;
            "browser.shell.checkDefaultBrowser" = false;
            "datareporting.policy.firstRunURL" = "";

            # Sponsored content on the new tab page.
            "browser.newtabpage.activity-stream.showSponsored" = false;
            "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
            "browser.newtabpage.activity-stream.feeds.section.topstories" = false;

            # Telemetry. The two datareporting prefs are the master switches
            # (upload disabled, policy never accepted); the rest cover the
            # subsystems that do not consult them -- health report, crash
            # reporter, Normandy remote experiments, and Shield studies.
            "datareporting.healthreport.uploadEnabled" = false;
            "datareporting.policy.dataSubmissionEnabled" = false;
            "toolkit.telemetry.enabled" = false;
            "toolkit.telemetry.unified" = false;
            "toolkit.telemetry.archive.enabled" = false;
            "toolkit.telemetry.newProfilePing.enabled" = false;
            "toolkit.telemetry.firstShutdownPing.enabled" = false;
            "toolkit.telemetry.shutdownPingSender.enabled" = false;
            "toolkit.telemetry.updatePing.enabled" = false;
            "toolkit.telemetry.bhrPing.enabled" = false;
            "toolkit.crashreporter.enabled" = false;
            "app.normandy.enabled" = false;
            "app.normandy.api_url" = "";
            "app.shield.optoutstudies.enabled" = false;
          };
        };
      };

      # Profile side of fx-autoconfig.
      #
      # chrome/utils must be a real directory of symlinks, not a symlink to one:
      # utils/chrome.manifest registers namespaces with relative paths
      # ("content userscripts ../JS/"), so if chrome/utils were itself a link
      # into the store, ".." would resolve inside /nix/store and every namespace
      # would break.
      home.file = {
        "${profileDir}/chrome/utils" = {
          source = "${fxAutoconfig}/profile/chrome/utils";
          recursive = true;
        };

        # fs.sys.mjs resolves the manifest's namespaces (userscripts -> ../JS,
        # userchrome -> ../resources, userstyles -> ../CSS) from a *static
        # initialisation block* that runs on module evaluation. A missing
        # directory throws there, which fails the boot.sys.mjs import, which
        # config.js swallows in its catch -- a completely silent no-op. Every
        # directory the manifest names has to exist, even when empty.
        "${profileDir}/chrome/resources/.keep".text = "";

        "${profileDir}/chrome/JS/debug-bridge.uc.js".source =
          "${chromeSrc}/JS/debug-bridge.uc.js";

        # Agent sheet, hiding the "Sidebery [x]" header Firefox draws above
        # extension sidebars. Must live in chrome/CSS (the "userstyles"
        # namespace) rather than chrome/JS: boot.sys.mjs scans only the style
        # dir for *.uc.css, so a .uc.css under chrome/JS is silently ignored.
        #
        # Agent scope is what makes it work at all -- the header is in
        # webext-panels.xhtml, a document neither userChrome.css nor Sidebery's
        # sidebarCSS can reach. See the comment in the file.
        "${profileDir}/chrome/CSS/webext-panel-header.uc.css".source =
          "${chromeSrc}/CSS/webext-panel-header.uc.css";

        # Reachable as chrome://userstyles/skin/sidebery.css. Sidebery's own
        # in-panel styling; pure Sidebery DOM classes, so it carried over from
        # the Zen setup unchanged.
        "${profileDir}/chrome/CSS/sidebery.css".source =
          "${chromeSrc}/CSS/sidebery.css";
      };

      # Store files always carry a 1970 mtime, so Firefox's startup cache will
      # not invalidate itself when a script changes. Dropping it every switch
      # costs one slightly slower start and avoids debugging stale scripts.
      home.activation.firefoxNeoClearStartupCache =
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run rm -rf ${lib.escapeShellArg "${config.home.homeDirectory}/${profileDir}/startupCache"}
          run rm -rf ${lib.escapeShellArg "${config.xdg.cacheHome}/mozilla/firefox/${profileName}/startupCache"}
        '';
    };
}
