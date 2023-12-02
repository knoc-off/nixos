{
  # I think its a bad idea to set this, but it could allow pre-configureations to work nicer
  #"browser.uiCustomization.state"

  # Make zoom more gradual
  "toolkit.zoomManager.zoomValues" =
    "0.30,0.32,0.34,0.36,0.38,0.40,0.42,0.44,0.46,0.48,0.50,0.52,0.54,0.56,0.58,0.60,0.62,0.64,0.66,0.68,0.70,0.72,0.74,0.76,0.78,0.80,0.82,0.84,0.86,0.88,0.90,0.92,0.94,0.96,0.98,1.0,1.02,1.04,1.06,1.08,1.10,1.12,1.14,1.16,1.18,1.20,1.22,1.24,1.26,1.28,1.30,1.32,1.34,1.36,1.38,1.40,1.42,1.44,1.46,1.48,1.50,1.52,1.54,1.56,1.58,1.60,1.62,1.64,1.66,1.68,1.70,1.72,1.74,1.76,1.78,1.80,1.82,1.84,1.86,1.88,1.90,1.92,1.94,1.96,1.98,2";

  # Enable HTTPS-Only Mode
  "dom.security.https_only_mode" = true;
  "dom.security.https_only_mode_ever_enabled" = true;

  # Privacy settings
  "privacy.trackingprotection.pbmode.enabled" = true;
  "privacy.usercontext.about_newtab_segregation.enabled" = true;
  "security.ssl.disable_session_identifiers" = true;
  "signon.autofillForms" = false;

  "media.eme.enabled" = false;
  "media.gmp-widevinecdm.enabled" = false;
  "network.cookie.cookieBehavior" = 1;

  "network.http.referer.trimmingPolicy" = 0;
  "beacon.enabled" = false;
  "browser.cache.offline.enable" = false;
  "browser.disableResetPrompt" = true;
  "browser.fixup.alternate.enabled" = false;
  "browser.newtab.preload" = false;

  "browser.newtabpage.activity-stream.disableSnippets" = true;
  "browser.newtabpage.activity-stream.enabled" = false;
  "browser.newtabpage.activity-stream.feeds.section.highlights" = false;
  "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
  "browser.newtabpage.activity-stream.feeds.snippets" = false;
  "browser.newtabpage.activity-stream.feeds.topsites" = false;
  "browser.newtabpage.activity-stream.migrationExpired" = true;
  "browser.newtabpage.activity-stream.prerender" = false;
  "browser.newtabpage.activity-stream.showSearch" = false;
  "browser.newtabpage.activity-stream.showTopSites" = false;

  "browser.newtabpage.directory.source" = "";
  "browser.newtabpage.directory.ping" = "";
  "browser.newtabpage.enabled" = false;
  "browser.newtabpage.enhanced" = false;
  "browser.newtabpage.introShown" = true;

  "browser.newtabpage.activity-stream.impressionId" = "";
  "browser.selfsupport.url" = "";
  "browser.send_pings" = false;
  "browser.shell.checkDefaultBrowser" = false;
  "browser.startup.homepage_override.mstone" = "ignore";
  "datareporting.healthreport.service.enabled" = false;
  "dom.battery.enabled" = false;
  "dom.enable_performance" = false;
  "dom.enable_resource_timing" = false;

  "dom.webaudio.enabled" = false;
  "extensions.getAddons.cache.enabled" = false;
  "extensions.getAddons.showPane" = false;
  "extensions.greasemonkey.stats.optedin" = false;
  "extensions.greasemonkey.stats.url" = "";
  "extensions.webservice.discoverURL" = "";
  "geo.enabled" = false;
  "media.navigator.enabled" = false;

  "privacy.donottrackheader.enabled" = true;
  "privacy.trackingprotection.enabled" = true;
  "privacy.trackingprotection.socialtracking.enabled" = true;
  "privacy.partition.network_state.ocsp_cache" = true;

  ## New Tab
  # Sponsors
  "browser.newtabpage.activity-stream.showSponsored" = false;
  "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
  # pinned
  "browser.newtabpage.activity-stream.improvesearch.topSiteSearchShortcuts.havePinned" =
    "";
  "browser.newtabpage.activity-stream.improvesearch.topSiteSearchShortcuts.searchEngines" =
    "";
  "browser.newtabpage.activity-stream.default.sites" = "";
  "browser.newtabpage.blocked" = "";
  "browser.search.hiddenOneOffs" = "Amazon.de,Bing,Google,Wikipedia (en)";

  # Disable all sorts of telemetry
  "browser.newtabpage.activity-stream.telemetry.structuredIngestion.endpoint" =
    "";
  "browser.newtabpage.activity-stream.feeds.telemetry" = false;
  "browser.newtabpage.activity-stream.telemetry" = false;
  "browser.ping-centre.telemetry" = false;
  "devtools.onboarding.telemetry.logged" = false;
  "toolkit.telemetry.unifiedIsOptIn" = false;
  "toolkit.telemetry.archive.enabled" = false;
  "toolkit.telemetry.bhrPing.enabled" = false;
  "toolkit.telemetry.enabled" = false;
  "toolkit.telemetry.rejected" = true;
  "toolkit.telemetry.firstShutdownPing.enabled" = false;
  "toolkit.telemetry.hybridContent.enabled" = false;
  "toolkit.telemetry.newProfilePing.enabled" = false;
  "toolkit.telemetry.reportingpolicy.firstRun" = false;
  "toolkit.telemetry.shutdownPingSender.enabled" = false;
  "toolkit.telemetry.unified" = false;
  "toolkit.telemetry.updatePing.enabled" = false;
  "toolkit.telemetry.server" = "";
  "toolkit.telemetry.prompted" = 2;
  "toolkit.telemetry.cachedClientID" = "";

  # As well as Firefox 'experiments'
  "experiments.activeExperiment" = false;
  "experiments.enabled" = false;
  "experiments.supported" = false;
  "network.allow-experiments" = false;

  # Disable Pocket Integration
  "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
  "extensions.pocket.enabled" = false;
  "extensions.pocket.api" = "";
  "extensions.pocket.oAuthConsumerKey" = "";
  "extensions.pocket.showHome" = false;
  "extensions.pocket.site" = "";

  ### More Privacy settings ###
  "datareporting.sessions.current.clean" = true;
  "datareporting.healthreport.uploadEnabled" = false;
  "datareporting.policy.dataSubmissionEnabled" = false;
  #"dom.push.userAgentID" = "";

  ## Fission
  "fission.autostart" = true;

  ## WebRender
  "gfx.webrender.all" = true;

  #"webgl.disabled" = true;
  #"webgl.renderer-string-override" = " ";
  #"webgl.vendor-string-override" = " ";

  ### Privacy /\

  #### Theme Settings ####
  ## personal
  "ui.key.menuAccessKeyFocuses" = false;
  "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
  "browser.urlbar.showSearchSuggestionsFirst" = false;
  "browser.tabs.insertAfterCurrent" = true;
  "browser.tabs.inTitlebar" = "2";

  ## Photon theme
  # Defaults
  "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
  "browser.proton.places-tooltip.enabled" = true;
  "svg.context-properties.content.enabled" = true;
  "layout.css.color-mix.enabled" = true;
  "layout.css.backdrop-filter.enabled" = true;
  "browser.compactmode.show" = true;
  "browser.newtabpage.activity-stream.improvesearch.handoffToAwesomebar" =
    false;
  "layout.css.has-selector.enabled" = true;

  # Related Options
  "userChrome.tab.connect_to_window" = true;
  "userChrome.tab.color_like_toolbar" = true;
  "userChrome.tab.lepton_like_padding" = false;
  "userChrome.tab.photon_like_padding" = true;
  "userChrome.tab.dynamic_separtor" = false;
  "userChrome.tab.static_separator" = true;
  "userChrome.tab.static_separator.selected_accent" = false;
  "userChrome.tab.newtab_button_like_tab" = false;
  "userChrome.tab.newtab_button_smaller" = true;
  "userChrome.tab.newtab_button_proton" = false;
  "userChrome.icon.panel_full" = false;
  "userChrome.icon.panel_photon" = true;
  "userChrome.icon.panel_sparse" = false;
  "userChrome.tab.box_shadow" = false;
  "userChrome.tab.bottom_rounded_corner" = false;
  "userChrome.tab.photon_like_contextline" = true;
  "userChrome.rounding.square_tab" = true;

  # Theme Default Settings
  "layout.css.devPixelsPerPx" = "1.3"; # UI shrink
  "userChrome.compatibility.theme" = true;
  "userChrome.compatibility.os" = true;
  "userChrome.theme.built_in_contrast" = true;
  "userChrome.theme.system_default" = true;
  "userChrome.theme.proton_color" = true;
  "userChrome.theme.proton_chrome" = true;
  "userChrome.theme.fully_color" = true;
  "userChrome.theme.fully_dark" = true;
  "userChrome.decoration.cursor" = true;
  "userChrome.decoration.field_border" = true;
  "userChrome.decoration.download_panel" = true;
  "userChrome.decoration.animate" = true;

  "userChrome.padding.tabbar_width" = true;
  "userChrome.padding.tabbar_height" = true;
  "userChrome.padding.toolbar_button" = true;
  "userChrome.padding.navbar_width" = true;
  "userChrome.padding.urlbar" = true;
  "userChrome.padding.bookmarkbar" = true;
  "userChrome.padding.infobar" = true;
  "userChrome.padding.menu" = true;
  "userChrome.padding.bookmark_menu" = true;
  "userChrome.padding.global_menubar" = true;
  "userChrome.padding.panel" = true;
  "userChrome.padding.popup_panel" = true;

  "userChrome.tab.multi_selected" = true;
  "userChrome.tab.unloaded" = true;
  "userChrome.tab.letters_cleary" = true;
  "userChrome.tab.close_button_at_hover" = true;
  "userChrome.tab.sound_hide_label" = true;
  "userChrome.tab.sound_with_favicons" = true;
  "userChrome.tab.pip" = true;
  "userChrome.tab.container" = true;
  "userChrome.tab.crashed" = true;

  "userChrome.fullscreen.overlap" = true;
  "userChrome.fullscreen.show_bookmarkbar" = true;

  "userChrome.icon.library" = true;
  "userChrome.icon.panel" = true;
  "userChrome.icon.menu" = true;
  "userChrome.icon.context_menu" = true;
  "userChrome.icon.global_menu" = true;
  "userChrome.icon.global_menubar" = true;

  # User Content
  "userContent.player.ui" = true;
  "userContent.player.icon" = true;
  "userContent.player.noaudio" = true;
  "userContent.player.size" = true;
  "userContent.player.click_to_play" = true;
  "userContent.player.animate" = true;

  "userContent.newTab.field_border" = true;
  "userContent.newTab.full_icon" = true;
  "userContent.newTab.animate" = true;
  "userContent.newTab.pocket_to_last" = true;
  "userContent.newTab.searchbar" = true;

  "userContent.page.illustration" = true;
  "userContent.page.proton_color" = true;
  "userContent.page.dark_mode" = true;
  "userContent.page.proton" = true;

  # Useful Options
  "browser.urlbar.suggest.calculator" = true;
  "browser.urlbar.unitConversion.enabled" = true;

  # Smooth Scroll
  "general.autoScroll" = true; # Scroll with middle mouse click
  "apz.allow_zooming" = true;
  "apz.force_disable_desktop_zooming_scrollbars" = false;
  "apz.paint_skipping.enabled" = true;
  "apz.windows.use_direct_manipulation" = true;
  "dom.event.wheel-deltaMode-lines.always-disabled" = true;
  "general.smoothScroll.currentVelocityWeighting" = "0.12";
  "general.smoothScroll.durationToIntervalRatio" = 1000;
  "general.smoothScroll.lines.durationMaxMS" = 100;
  "general.smoothScroll.lines.durationMinMS" = 0;
  "general.smoothScroll.mouseWheel.durationMaxMS" = 100;
  "general.smoothScroll.mouseWheel.durationMinMS" = 0;
  "general.smoothScroll.mouseWheel.migrationPercent" = 100;
  "general.smoothScroll.msdPhysics.continuousMotionMaxDeltaMS" = 12;
  "general.smoothScroll.msdPhysics.enabled" = true;
  "general.smoothScroll.msdPhysics.motionBeginSpringConstant" = 200;
  "general.smoothScroll.msdPhysics.regularSpringConstant" = 200;
  "general.smoothScroll.msdPhysics.slowdownMinDeltaMS" = 10;
  "general.smoothScroll.msdPhysics.slowdownMinDeltaRatio" = "1.20";
  "general.smoothScroll.msdPhysics.slowdownSpringConstant" = 1000;
  "general.smoothScroll.other.durationMaxMS" = 100;
  "general.smoothScroll.other.durationMinMS" = 0;
  "general.smoothScroll.pages.durationMaxMS" = 100;
  "general.smoothScroll.pages.durationMinMS" = 0;
  "general.smoothScroll.pixels.durationMaxMS" = 100;
  "general.smoothScroll.pixels.durationMinMS" = 0;
  "general.smoothScroll.scrollbars.durationMaxMS" = 100;
  "general.smoothScroll.scrollbars.durationMinMS" = 0;
  "general.smoothScroll.stopDecelerationWeighting" = "0.6";
  "layers.async-pan-zoom.enabled" = true;
  "layout.css.scroll-behavior.spring-constant" = "250.0";
  "mousewheel.acceleration.factor" = 3;
  "mousewheel.acceleration.start" = -1;
  "mousewheel.default.delta_multiplier_x" = 50;
  "mousewheel.default.delta_multiplier_y" = 50;
  "mousewheel.default.delta_multiplier_z" = 50;
  "mousewheel.min_line_scroll_amount" = 0;
  "mousewheel.system_scroll_override.enabled" = true;
  "mousewheel.system_scroll_override_on_root_content.enabled" = false;
  "mousewheel.transaction.timeout" = 1500;
  "toolkit.scrollbox.horizontalScrollDistance" = 4;
  "toolkit.scrollbox.verticalScrollDistance" = 3;
}
