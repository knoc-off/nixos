{ pkgs, theme }:
let
  firefox-csshacks = pkgs.fetchFromGitHub {
    owner = "MrOtherGuy";
    repo = "firefox-csshacks";
    rev = "31cb27a5d8e11a4f35499ea9d75cc9939399d915";
    sha256 = "sha256-ALLqHSEk4oC0/KsALYmQyXg4GtxYiOy4bquLjC+dhng=";
  };
in
''
  /* Import necessary CSS hacks */
  /* @import "${firefox-csshacks}/content/"; */
  @import "${firefox-csshacks}/content/auto_devtools_theme.css";


  /*
   @import "${firefox-csshacks}/content/about_page_scrollbars.css"
   @import "${firefox-csshacks}/content/auto_devtools_theme.css"
   @import "${firefox-csshacks}/content/css_scrollbar_width_color.css"
   @import "${firefox-csshacks}/content/limit_css_data_leak.css"
   @import "${firefox-csshacks}/content/newtab_background_image.css"

   @import "${firefox-csshacks}/content/remove_textbox_focusring.css"
   @import "${firefox-csshacks}/content/high_contrast_extended_style.css"
   @import "${firefox-csshacks}/content/addon_manage_buttons_without_popup.css"
   @import "${firefox-csshacks}/content/compact_about_config.css"
   @import "${firefox-csshacks}/content/compact_addons_manager.css"
   @import "${firefox-csshacks}/content/dark_settings_pages.css"
   @import "${firefox-csshacks}/content/multi_column_addons.css"
   @import "${firefox-csshacks}/content/newtab_background_color.css"
   @import "${firefox-csshacks}/content/standalone_image_page_mods.css"
   @import "${firefox-csshacks}/content/transparent_reader_toolbar.css"
  */
   @import "${firefox-csshacks}/content/two_column_addons.css"
''
