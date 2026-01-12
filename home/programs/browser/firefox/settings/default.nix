{
  theme,
  color-lib,
  lib,
  ...
}: {
  # =========================================================================
  # Core Functionality & Performance
  # =========================================================================

  # auto enable extensions
  "extensions.autoDisableScopes" = 0;

  # Enable Fission (Site Isolation)
  "fission.autostart" = true;

  # Enable WebRender rendering engine
  "gfx.webrender.all" = true;

  # Enable Asynchronous Panning and Zooming (APZ)
  "layers.async-pan-zoom.enabled" = true;
  # # Also related to Scrolling/Zoom
  # "layers.async-pan-zoom.enabled" = true;

  # APZ settings (related to scrolling performance and behavior)
  "apz.allow_zooming" = true;
  "apz.force_disable_desktop_zooming_scrollbars" = false;
  "apz.paint_skipping.enabled" = true;
  "apz.windows.use_direct_manipulation" = true;
  # # Also related to Scrolling/Zoom
  # "apz.allow_zooming" = true;
  # "apz.force_disable_desktop_zooming_scrollbars" = false;
  # "apz.paint_skipping.enabled" = true;
  # "apz.windows.use_direct_manipulation" = true;

  # Fix GTK bug: https://bugzilla.mozilla.org/show_bug.cgi?id=1818517
  "widget.gtk.ignore-bogus-leave-notify" = 1;

  # =========================================================================
  # Theme & Appearance (Proton, Dark Mode, userChrome/userContent)
  # =========================================================================

  # Enable userChrome.css and userContent.css customizations
  "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

  # --- Dark Theme & Colors ---
  "devtools.theme" = "dark";
  # # Also related to Developer Tools
  # "devtools.theme" = "dark";
  "ui.systemUsesDarkTheme" = "1"; # Force dark theme detection
  # Set background colors (using placeholder Nix variables)
  # "browser.display.background_color" = "#${theme.dark.base00}"; # Requires theme variable
  # "browser.display.background_color.dark" = "#${theme.dark.base00}"; # Requires theme variable

  # --- General Theme Settings ---
  "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
  #"layout.css.devPixelsPerPx" = "1.3"; # UI Scale
  #"layout.css.devPixelsPerPx" = "2"; # MacOs
  # # Also related to UI Customization
  # "layout.css.devPixelsPerPx" = "1.3";

  # --- Proton UI Settings ---
  "browser.proton.places-tooltip.enabled" = true;
  "browser.compactmode.show" =
    true; # Show compact density option in customize menu

  # --- CSS Feature Flags (Often needed for themes) ---
  "svg.context-properties.content.enabled" = true;
  "layout.css.color-mix.enabled" = true;
  "layout.css.backdrop-filter.enabled" = true;
  "layout.css.has-selector.enabled" = true;

  # --- userChrome.css Theme Compatibility & Style ---
  "userChrome.compatibility.theme" = true;
  "userChrome.compatibility.os" = true;
  "userChrome.theme.built_in_contrast" = true;
  "userChrome.theme.system_default" = true;
  "userChrome.theme.proton_color" = true;
  "userChrome.theme.proton_chrome" = true;
  "userChrome.theme.fully_color" = true;
  "userChrome.theme.fully_dark" = true;

  # --- userChrome.css Decorations ---
  "userChrome.decoration.cursor" = true;
  "userChrome.decoration.field_border" = true;
  "userChrome.decoration.download_panel" = true;
  "userChrome.decoration.animate" = true;

  # --- userChrome.css Padding Adjustments ---
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

  # --- userChrome.css Tab Appearance & Behavior ---
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
  "userChrome.tab.pip" = true; # Picture-in-Picture indicator
  "userChrome.tab.container" = true; # Container tab indicator
  "userChrome.tab.crashed" = true; # Crashed tab indicator

  # --- userChrome.css Icon Styles ---
  "userChrome.icon.panel_full" = false;
  "userChrome.icon.panel_photon" = true;
  "userChrome.icon.panel_sparse" = false;
  "userChrome.icon.library" = true;
  "userChrome.icon.panel" = true;
  "userChrome.icon.menu" = true;
  "userChrome.icon.context_menu" = true;
  "userChrome.icon.global_menu" = true;
  "userChrome.icon.global_menubar" = true;

  # --- userChrome.css Fullscreen Behavior ---
  "userChrome.fullscreen.overlap" = true;
  "userChrome.fullscreen.show_bookmarkbar" = true;

  # --- userContent.css Media Player ---
  "userContent.player.ui" = true;
  "userContent.player.icon" = true;
  "userContent.player.noaudio" = true;
  "userContent.player.size" = true;
  "userContent.player.click_to_play" = true;
  "userContent.player.animate" = true;

  # --- userContent.css New Tab Page ---
  "userContent.newTab.field_border" = true;
  "userContent.newTab.full_icon" = true;
  "userContent.newTab.animate" = true;
  "userContent.newTab.pocket_to_last" = true;
  "userContent.newTab.searchbar" = true;

  # --- userContent.css Internal Pages (about:*) ---
  "userContent.page.illustration" = true;
  "userContent.page.proton_color" = true;
  "userContent.page.dark_mode" = true;
  "userContent.page.proton" = true;

  # --- colors ---
  "browser.active_color" = "#${theme.dark.base0E}"; # Active link color (light) - Using Magenta/Purple
  "browser.active_color.dark" = "#${theme.dark.base0E}"; # Active link color (dark) - Using Magenta/Purple
  "browser.anchor_color" = "#${theme.dark.base0D}"; # Link color (light) - Using Blue
  "browser.anchor_color.dark" = "#${theme.dark.base0D}"; # Link color (dark) - Using Blue
  "browser.display.background_color" = "#${theme.dark.base00}"; # Page background (light)
  "browser.display.background_color.dark" = "#${theme.dark.base01}"; # Page background (dark)
  "browser.display.foreground_color" = "#${theme.dark.base06}"; # Page text (light)
  "browser.display.foreground_color.dark" = "#${theme.dark.base07}"; # Page text (dark)
  # New Tab Page accent colors - using a sequence of base colors
  "browser.newtabpage.activity-stream.newNewtabExperience.colors" = "#${theme.dark.base08},#${theme.dark.base09},#${theme.dark.base0A},#${theme.dark.base0B},#${theme.dark.base0C},#${theme.dark.base0D},#${theme.dark.base0E}";
  "browser.visited_color" = "#${theme.dark.base0E}"; # Visited link color (light) - Using Magenta/Purple
  "browser.visited_color.dark" = "#${theme.dark.base0F}"; # Visited link color (dark) - Using Brown/Lighter Purple
  "editor.background_color" = "#${theme.dark.base01}"; # Text input background (light)
  # PDF.js highlight colors mapped to theme accents
  "pdfjs.highlightEditorColors" = "yellow=#${theme.dark.base0A},green=#${theme.dark.base0B},blue=#${theme.dark.base0D},pink=#${theme.dark.base0E},red=#${theme.dark.base08}";

  # =========================================================================
  # UI Customization (Behavior, Tabs, URL Bar)
  # =========================================================================

  # Disable menu access key focusing elements (Alt key behavior)
  "ui.key.menuAccessKeyFocuses" = false;

  # URL Bar behavior
  "browser.urlbar.showSearchSuggestionsFirst" = false;

  # Tab behavior
  "browser.tabs.insertAfterCurrent" = true; # Open new tabs next to current
  "browser.tabs.inTitlebar" = "2"; # For custom themes, might affect CSD

  # New Tab Page behavior (Search)
  "browser.newtabpage.activity-stream.improvesearch.handoffToAwesomebar" =
    false;

  # # UI Scale (Primary category: Theme & Appearance)
  # "layout.css.devPixelsPerPx" = "1.3";
  # layout.css.devPixelsPerPx = 2 # MacOs

  # =========================================================================
  # Zoom & Scrolling
  # =========================================================================

  # --- Zoom ---
  # Define custom zoom levels for finer control
  # "toolkit.zoomManager.zoomValues" = zoomValuesString;

  # --- Smooth Scrolling ---
  "general.autoScroll" = true; # Enable middle-mouse button scrolling
  "dom.event.wheel-deltaMode-lines.always-disabled" =
    true; # Use pixel scrolling mode

  # General Smooth Scroll settings
  "general.smoothScroll.currentVelocityWeighting" = "0.12";
  "general.smoothScroll.durationToIntervalRatio" = 1000;
  "general.smoothScroll.stopDecelerationWeighting" = "0.6";

  # Duration settings (lines, mouseWheel, other, pages, pixels, scrollbars)
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

  # MSD Physics based smooth scroll
  "general.smoothScroll.msdPhysics.enabled" = true;
  "general.smoothScroll.msdPhysics.continuousMotionMaxDeltaMS" = 12;
  "general.smoothScroll.msdPhysics.motionBeginSpringConstant" = 200;
  "general.smoothScroll.msdPhysics.regularSpringConstant" = 200;
  "general.smoothScroll.msdPhysics.slowdownMinDeltaMS" = 10;
  "general.smoothScroll.msdPhysics.slowdownMinDeltaRatio" = "1.20";
  "general.smoothScroll.msdPhysics.slowdownSpringConstant" = 1000;
  "general.smoothScroll.mouseWheel.migrationPercent" =
    100; # Fully use new physics

  # CSS Scroll Behavior
  "layout.css.scroll-behavior.spring-constant" = "250.0";

  # Mousewheel settings
  "mousewheel.acceleration.factor" = 3;
  "mousewheel.acceleration.start" = -1; # Disable acceleration threshold
  "mousewheel.default.delta_multiplier_x" = 50;
  "mousewheel.default.delta_multiplier_y" = 50;
  "mousewheel.default.delta_multiplier_z" = 50;
  "mousewheel.min_line_scroll_amount" = 0; # Use pixel scrolling
  "mousewheel.system_scroll_override.enabled" = true; # Override system settings
  "mousewheel.system_scroll_override_on_root_content.enabled" = false;
  "mousewheel.transaction.timeout" = 1500; # Timeout for scroll events

  # Scroll distance for scrollbox elements (e.g., bookmarks menu)
  "toolkit.scrollbox.horizontalScrollDistance" = 4;
  "toolkit.scrollbox.verticalScrollDistance" = 3;

  # # APZ settings (Primary category: Core & Performance)
  # "apz.allow_zooming" = true;
  # "apz.force_disable_desktop_zooming_scrollbars" = false;
  # "apz.paint_skipping.enabled" = true;
  # "apz.windows.use_direct_manipulation" = true;

  # # Async Pan/Zoom (Primary category: Core & Performance)
  # "layers.async-pan-zoom.enabled" = true;

  # =========================================================================
  # Features & Privacy (Pocket, etc.)
  # =========================================================================

  # Disable Pocket Integration
  "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
  "extensions.pocket.enabled" = false;
  "extensions.pocket.api" = "";
  "extensions.pocket.oAuthConsumerKey" = "";
  "extensions.pocket.showHome" = false;
  "extensions.pocket.site" = "";

  # =========================================================================
  # Developer Tools
  # =========================================================================

  # # DevTools Theme (Primary category: Theme & Appearance)
  # "devtools.theme" = "dark";

  # =========================================================================
  # WebGL (Commented Out - Disabled by default in snippets)
  # =========================================================================

  # "webgl.disabled" = true;
  # "webgl.renderer-string-override" = " ";
  # "webgl.vendor-string-override" = " ";
}
