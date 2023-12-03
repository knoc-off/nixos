{

  # so the userchrome.css file is used
  "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

  # Make zoom more gradual
  "toolkit.zoomManager.zoomValues" =
    "0.30,0.32,0.34,0.36,0.38,0.40,0.42,0.44,0.46,0.48,0.50,0.52,0.54,0.56,0.58,0.60,0.62,0.64,0.66,0.68,0.70,0.72,0.74,0.76,0.78,0.80,0.82,0.84,0.86,0.88,0.90,0.92,0.94,0.96,0.98,1.0,1.02,1.04,1.06,1.08,1.10,1.12,1.14,1.16,1.18,1.20,1.22,1.24,1.26,1.28,1.30,1.32,1.34,1.36,1.38,1.40,1.42,1.44,1.46,1.48,1.50,1.52,1.54,1.56,1.58,1.60,1.62,1.64,1.66,1.68,1.70,1.72,1.74,1.76,1.78,1.80,1.82,1.84,1.86,1.88,1.90,1.92,1.94,1.96,1.98,2";



  # Disable Pocket Integration
  "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
  "extensions.pocket.enabled" = false;
  "extensions.pocket.api" = "";
  "extensions.pocket.oAuthConsumerKey" = "";
  "extensions.pocket.showHome" = false;
  "extensions.pocket.site" = "";

  ## Fission
  "fission.autostart" = true;

  ## WebRender
  "gfx.webrender.all" = true;

  #"webgl.disabled" = true;
  #"webgl.renderer-string-override" = " ";
  #"webgl.vendor-string-override" = " ";

  #### Theme Settings ####
  ## personal
  "ui.key.menuAccessKeyFocuses" = false;
  "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
  "browser.urlbar.showSearchSuggestionsFirst" = false;
  "browser.tabs.insertAfterCurrent" = true;
  "browser.tabs.inTitlebar" = "2";

  ## Photon theme
  # Defaults
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
