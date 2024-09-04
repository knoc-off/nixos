{ theme }:

{
  # Dark theme
  "devtools.theme" = "dark";
  "browser.display.background_color" = "#${theme.base02}";
  "browser.display.background_color.dark" = "#${theme.base02}";
  "ui.systemUsesDarkTheme" = "1";

  # Theme settings
  "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
  "layout.css.devPixelsPerPx" = "1.3"; # Scale of the UI

  # Photon theme defaults
  "browser.proton.places-tooltip.enabled" = true;
  "svg.context-properties.content.enabled" = true;
  "layout.css.color-mix.enabled" = true;
  "layout.css.backdrop-filter.enabled" = true;
  "browser.compactmode.show" = true;
  "layout.css.has-selector.enabled" = true;

  # UserChrome theme settings
  "userChrome.compatibility.theme" = true;
  "userChrome.compatibility.os" = true;
  "userChrome.theme.built_in_contrast" = true;
  "userChrome.theme.system_default" = true;
  "userChrome.theme.proton_color" = true;
  "userChrome.theme.proton_chrome" = true;
  "userChrome.theme.fully_color" = true;
  "userChrome.theme.fully_dark" = true;
}
