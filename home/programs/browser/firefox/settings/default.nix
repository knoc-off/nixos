{
  theme,
  color-lib,
  lib,
  ...
}: {
  "extensions.autoDisableScopes" = 0;

  "fission.autostart" = true;

  "gfx.webrender.all" = true;

  "layers.async-pan-zoom.enabled" = true;

  "apz.allow_zooming" = true;
  "apz.force_disable_desktop_zooming_scrollbars" = false;
  "apz.paint_skipping.enabled" = true;
  "apz.windows.use_direct_manipulation" = true;

  "widget.gtk.ignore-bogus-leave-notify" = 1;

  "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

  "devtools.theme" = "dark";
  "ui.systemUsesDarkTheme" = "1";

  "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";

  "browser.proton.places-tooltip.enabled" = true;
  "browser.compactmode.show" = true;

  "svg.context-properties.content.enabled" = true;
  "layout.css.color-mix.enabled" = true;
  "layout.css.backdrop-filter.enabled" = true;
  "layout.css.has-selector.enabled" = true;

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
  "userChrome.tab.box_shadow" = false;
  "userChrome.tab.bottom_rounded_corner" = false;
  "userChrome.tab.photon_like_contextline" = true;
  "userChrome.rounding.square_tab" = true;
  "userChrome.tab.multi_selected" = true;
  "userChrome.tab.unloaded" = true;
  "userChrome.tab.letters_cleary" = true;
  "userChrome.tab.close_button_at_hover" = true;
  "userChrome.tab.sound_hide_label" = true;
  "userChrome.tab.sound_with_favicons" = true;
  "userChrome.tab.pip" = true;
  "userChrome.tab.container" = true;
  "userChrome.tab.crashed" = true;

  "userChrome.icon.panel_full" = false;
  "userChrome.icon.panel_photon" = true;
  "userChrome.icon.panel_sparse" = false;
  "userChrome.icon.library" = true;
  "userChrome.icon.panel" = true;
  "userChrome.icon.menu" = true;
  "userChrome.icon.context_menu" = true;
  "userChrome.icon.global_menu" = true;
  "userChrome.icon.global_menubar" = true;

  "userChrome.fullscreen.overlap" = true;
  "userChrome.fullscreen.show_bookmarkbar" = true;

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

  "browser.active_color" = "#${theme.dark.base0E}";
  "browser.active_color.dark" = "#${theme.dark.base0E}";
  "browser.anchor_color" = "#${theme.dark.base0D}";
  "browser.anchor_color.dark" = "#${theme.dark.base0D}";
  "browser.display.background_color" = "#${theme.dark.base00}";
  "browser.display.background_color.dark" = "#${theme.dark.base01}";
  "browser.display.foreground_color" = "#${theme.dark.base06}";
  "browser.display.foreground_color.dark" = "#${theme.dark.base07}";
  "browser.newtabpage.activity-stream.newNewtabExperience.colors" = "#${theme.dark.base08},#${theme.dark.base09},#${theme.dark.base0A},#${theme.dark.base0B},#${theme.dark.base0C},#${theme.dark.base0D},#${theme.dark.base0E}";
  "browser.visited_color" = "#${theme.dark.base0E}";
  "browser.visited_color.dark" = "#${theme.dark.base0F}";
  "editor.background_color" = "#${theme.dark.base01}";
  "pdfjs.highlightEditorColors" = "yellow=#${theme.dark.base0A},green=#${theme.dark.base0B},blue=#${theme.dark.base0D},pink=#${theme.dark.base0E},red=#${theme.dark.base08}";

  "ui.key.menuAccessKeyFocuses" = false;

  "browser.urlbar.showSearchSuggestionsFirst" = false;

  "browser.tabs.insertAfterCurrent" = true;
  "browser.tabs.inTitlebar" = "2";

  "browser.newtabpage.activity-stream.improvesearch.handoffToAwesomebar" = false;

  "general.autoScroll" = true;
  "dom.event.wheel-deltaMode-lines.always-disabled" = true;

  "general.smoothScroll.currentVelocityWeighting" = "0.12";
  "general.smoothScroll.durationToIntervalRatio" = 1000;
  "general.smoothScroll.stopDecelerationWeighting" = "0.6";

  "general.smoothScroll.lines.durationMaxMS" = 100;
  "general.smoothScroll.lines.durationMinMS" = 0;
  "general.smoothScroll.mouseWheel.durationMaxMS" = 100;
  "general.smoothScroll.mouseWheel.durationMinMS" = 0;
  "general.smoothScroll.other.durationMaxMS" = 100;
  "general.smoothScroll.other.durationMinMS" = 0;
  "general.smoothScroll.pages.durationMaxMS" = 100;
  "general.smoothScroll.pages.durationMinMS" = 0;
  "general.smoothScroll.pixels.durationMaxMS" = 100;
  "general.smoothScroll.pixels.durationMinMS" = 0;
  "general.smoothScroll.scrollbars.durationMaxMS" = 100;
  "general.smoothScroll.scrollbars.durationMinMS" = 0;

  "general.smoothScroll.msdPhysics.enabled" = true;
  "general.smoothScroll.msdPhysics.continuousMotionMaxDeltaMS" = 12;
  "general.smoothScroll.msdPhysics.motionBeginSpringConstant" = 200;
  "general.smoothScroll.msdPhysics.regularSpringConstant" = 200;
  "general.smoothScroll.msdPhysics.slowdownMinDeltaMS" = 10;
  "general.smoothScroll.msdPhysics.slowdownMinDeltaRatio" = "1.20";
  "general.smoothScroll.msdPhysics.slowdownSpringConstant" = 1000;
  "general.smoothScroll.mouseWheel.migrationPercent" = 100;

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

  "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
  "extensions.pocket.enabled" = false;
  "extensions.pocket.api" = "";
  "extensions.pocket.oAuthConsumerKey" = "";
  "extensions.pocket.showHome" = false;
  "extensions.pocket.site" = "";
}
