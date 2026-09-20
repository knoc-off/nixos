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
      browserExec = self.packages.${pkgs.stdenv.hostPlatform.system}.browser-exec;
      fxAutoconfig = inputs.fx-autoconfig;

      profileName = "neo";
      configPath = "${config.xdg.configHome}/mozilla/firefox";
      profileDir = "${configPath}/${profileName}";

      # Userscripts and userstyles, installed into the profile below.
      chromeSrc = ./chrome;
      browserExecChrome = "${browserExec}/lib/browser-exec/chrome";
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
              dearrow
              sponsorblock
              violentmonkey
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
                  # Built in theme.nix rather than read directly here: it needs
                  # the palette prepended as --neo-base* custom properties. This
                  # value is stored in extension storage, so it has to be the
                  # CSS text, not a reference to it.
                  sidebarCSS = neoTheme.sidebarCSS;
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
          # the imported sheet below consumes those variables.
          #
          # sidebery-collapse.css is standalone now; the autohide_sidebar.css
          # import it used to retarget is gone, since Sidebery has its own
          # frame (chrome/JS/neo-sidebar.uc.js) and csshacks' hardcoded
          # #sidebar-box rules would clamp the native sidebar along with it.
          #
          # @import must precede all other rules in a stylesheet, so the
          # import leads and the variable block follows.
          userChrome = ''
            @import "${chromeSrc}/CSS/sidebery-collapse.css";

            ${neoTheme.userChrome}
          '';

          # In-content pages (about:config, about:addons, about:preferences)
          # are styled by the design-token system, not by --lwt-*, so they need
          # their own sheet. Without this they keep Firefox 154's violet
          # "nova" accent regardless of what the chrome is themed to.
          userContent = neoTheme.userContent;

          search = import ./searchEngines.nix { inherit pkgs lib; };

          settings = neoTheme.settings // {
            # Required for userChrome.css to be read at all.
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

            # Required for the @-moz-document url-prefix("about:") wrapper in
            # userContent.css (theme.nix) to be honored, scoping those rules to
            # Firefox's own about: pages instead of every document loaded.
            "layout.css.moz-document.content.enabled" = true;

            # Suppresses fx-autoconfig's own first-run infobar ("Firefox is
            # being modified with custom autoconfig scripting"). boot.sys.mjs
            # shows it via `Pref.setIfUnset("userChromeJS.firstRunShown", true)`,
            # which returns true only when it actually had to set the pref --
            # so presetting it means the notification never fires. Worth doing
            # declaratively rather than dismissing it once: pkgs/jailed-firefox-neo
            # gets a fresh profile on every launch, where "once" is every time.
            "userChromeJS.firstRunShown" = true;

            # Drag-and-drop fix. Under GTK/Wayland the compositor sends a
            # spurious LeaveNotify during a drag, which Firefox reads as the
            # pointer having left the window -- so the drag aborts partway and
            # the drop never lands. Tab reordering and dragging a tab into
            # Sidebery are the visible symptoms.
            #
            # Carried over from modules/firefox (settings/default.nix); it was
            # needed for Zen too. Not inherited automatically because this
            # module deliberately does not import that one.
            "widget.gtk.ignore-bogus-leave-notify" = 1;

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

            # The built-in AI chat registers itself as a sidebar tool, and the
            # revamp sidebar has exactly one slot -- so enabling it evicts
            # whatever was in there. Unused here, so turn it off at the source
            # rather than just hiding its entry.
            #
            # Note this is no longer load-bearing for keeping tabs visible:
            # Sidebery has its own frame now (chrome/JS/neo-sidebar.uc.js) and
            # cannot be evicted by anything. It is off because it is unwanted,
            # not because it would break the layout.
            "browser.ml.chat.enabled" = false;

            # NOTE: Sidebery is kept out of sidebar.main.tools too, but that
            # cannot be done here -- its manifest sets open_at_install, so
            # Firefox appends the id back after prefs load and a declarative
            # value loses the race. chrome/JS/neo-sidebar.uc.js strips it at
            # runtime instead. Bitwarden keeps the native sidebar.

            # Chrome-level devtools access, used by browser-exec's bridge
            # sandbox (system-principal Cu.Sandbox needs this to eval).
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

        # browser-exec: unix-socket chrome/page eval bridge (supersedes the
        # old TCP debug-bridge.uc.js) and the fx-autoconfig userscript loader
        # it exposes reloadUserscripts() for. See pkgs/browser-exec.
        #
        # The bridge is a *.sys.mjs, not a *.uc.js: it must be imported once
        # per process into the shared module global rather than injected into
        # each chrome window, or the socket it binds dies with whichever
        # window happened to load it.
        "${profileDir}/chrome/JS/bridge.sys.mjs".source = "${browserExecChrome}/JS/bridge.sys.mjs";
        "${profileDir}/chrome/JS/loader.sys.mjs".source = "${browserExecChrome}/JS/loader.sys.mjs";
        "${profileDir}/chrome/JS/match.mjs".source = "${browserExecChrome}/JS/match.mjs";
        "${profileDir}/chrome/JS/actor" = {
          source = "${browserExecChrome}/JS/actor";
          recursive = true;
        };

        # Builds the dedicated Sidebery sidebar, so the extension is not
        # competing with Bitwarden/AI chat/etc for the single native slot.
        # Styled by the #neo-sidebar-box rules in sidebery-collapse.css.
        "${profileDir}/chrome/JS/neo-sidebar.uc.js".source = "${chromeSrc}/JS/neo-sidebar.uc.js";

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
        "${profileDir}/chrome/CSS/sidebery.css".source = "${chromeSrc}/CSS/sidebery.css";
      };

      # Store files always carry a 1970 mtime, so Firefox's startup cache will
      # not invalidate itself when a script changes. Dropping it every switch
      # costs one slightly slower start and avoids debugging stale scripts.
      home.activation.firefoxNeoClearStartupCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run rm -rf ${lib.escapeShellArg "${config.home.homeDirectory}/${profileDir}/startupCache"}
        run rm -rf ${lib.escapeShellArg "${config.xdg.cacheHome}/mozilla/firefox/${profileName}/startupCache"}
      '';
    };
}
