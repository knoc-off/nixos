{theme}: {
  # so the userchrome.css file is used
  "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

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

  #### Theme Settings ####
  ## personal
  "ui.key.menuAccessKeyFocuses" = false;
  "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
  "browser.urlbar.showSearchSuggestionsFirst" = false;
  "browser.tabs.insertAfterCurrent" = true;
  "browser.tabs.inTitlebar" = "2";

  "layout.css.devPixelsPerPx" = "1.3";

  # Smooth Scroll
  "general.autoScroll" = false; # Scroll with middle mouse click
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
