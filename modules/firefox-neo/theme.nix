# Theme derivation for firefox-neo: one Base16 palette from theme.nix, applied
# to Firefox through the three mechanisms that do not require an unsigned
# add-on.
#
# Why not a generated theme XPI, which would be the obvious answer: nixpkgs
# builds Firefox with requireSigning = true and allowAddonSideload = false, and
# release builds enforce signing at compile time -- no pref relaxes it
# (wrapper.nix throws outright if you pass nixExtensions without both flipped).
# Flipping them means rebuilding Firefox from source with no binary cache. So
# theming goes through:
#
#   prefs        -- content area (page bg/fg, link colors, pdf.js, highlights)
#   userChrome   -- the browser chrome, by overriding Firefox's own --lwt-*
#                   custom properties. Reaches parts the theme API cannot.
#   colorTheme   -- the firefox-color extension's stored theme, which drives
#                   the same colors the official theme API does.
#
# Both palettes are emitted; the chrome CSS switches on prefers-color-scheme so
# the browser follows the system rather than pinning dark.
{ theme, color-lib }:
let
  # theme.nix returns bare hex with no leading "#".
  css = hex: "#${hex}";

  # The theme API wants integer channels, not hex. color-lib.hexToRgb returns
  # 0.0-1.0 floats, so the scale factor is 255 -- note modules/firefox uses 256
  # here, which can emit an out-of-range 256 for a full channel.
  rgba =
    hex:
    let
      round = x: builtins.floor (x + 0.5);
      c = color-lib.hexToRgb hex;
    in
    {
      r = round (c.r * 255);
      g = round (c.g * 255);
      b = round (c.b * 255);
      a = c.alpha;
    };

  # Firefox's chrome is themed through --lwt-* / --toolbar-* custom properties
  # that the built-in themes set. Assigning them directly on :root reaches the
  # toolbar, urlbar, tab strip, panels and sidebar in one pass, and unlike the
  # theme API it survives without any extension installed.
  chromeVars = c: ''
    --lwt-accent-color: ${css c.base00};
    --lwt-accent-color-inactive: ${css c.base00};
    --lwt-text-color: ${css c.base05};

    --toolbar-bgcolor: ${css c.base01};
    --toolbar-color: ${css c.base05};
    --toolbar-field-background-color: ${css c.base02};
    --toolbar-field-color: ${css c.base05};
    --toolbar-field-focus-background-color: ${css c.base01};
    --toolbar-field-focus-color: ${css c.base06};
    --toolbar-field-border-color: ${css c.base03};
    --toolbar-field-focus-border-color: ${css c.base0D};
    --lwt-toolbar-field-highlight: ${css c.base02};
    --lwt-toolbar-field-highlight-text: ${css c.base07};

    --lwt-toolbarbutton-icon-fill: ${css c.base05};
    --lwt-toolbarbutton-icon-fill-attention: ${css c.base09};
    --lwt-toolbarbutton-hover-background: ${css c.base02};
    --lwt-toolbarbutton-active-background: ${css c.base03};

    --tab-selected-bgcolor: ${css c.base01};
    --tab-selected-textcolor: ${css c.base05};
    --tab-line-color: ${css c.base0D};
    --tab-loading-fill: ${css c.base0C};
    --lwt-tab-text: ${css c.base05};

    --arrowpanel-background: ${css c.base01};
    --arrowpanel-color: ${css c.base05};
    --arrowpanel-border-color: ${css c.base03};
    --panel-separator-color: ${css c.base02};
    --panel-item-hover-bgcolor: ${css c.base02};
    --panel-item-active-bgcolor: ${css c.base03};

    --lwt-sidebar-background-color: ${css c.base00};
    --lwt-sidebar-text-color: ${css c.base05};
    --sidebar-border-color: ${css c.base03};

    --urlbar-box-bgcolor: ${css c.base02};
    --urlbar-box-text-color: ${css c.base05};
    --urlbar-box-hover-bgcolor: ${css c.base03};

    --focus-outline-color: ${css c.base0D};
    --link-color: ${css c.base0D};
    --link-color-hover: ${css c.base0C};
    --error-text-color: ${css c.base08};
    --warning-text-color: ${css c.base0A};
    --success-text-color: ${css c.base0B};
  '';

  # Native menus (right-click context menu, the menubar drop-downs) are NOT
  # covered by chromeVars above, and this is not an oversight in the list: they
  # do not read --arrowpanel-* at all. chrome://global/skin/popup.css:9-10 sets
  #
  #   :is(menupopup, panel):where(:not([type="arrow"])) {
  #     --panel-background-color: Menu;
  #     --panel-text-color: MenuText;
  #   }
  #
  # -- different variables, and hardcoded to the *system* palette. Two
  # consequences, both verified over the debug bridge:
  #
  #   1. It has to be its own selector. popup.css sets the variable on the
  #      menupopup element itself, so a value inherited from :root loses; an
  #      inline style on the shadow part loses too (measured: no effect).
  #   2. Menu/MenuText resolve from Firefox's built-in dark theme, not from
  #      anything themeable -- Menu measured as rgb(54,54,58) against our
  #      base01 #323F47, which is exactly the mismatch that showed up.
  #
  # Hover is a third case again: chrome://global/skin/menu.css:252-253 uses the
  # bare keywords -moz-menuhover / -moz-menuhovertext with no variable in
  # between (measured rgb(21,83,158), the stock blue), so it needs a direct
  # rule rather than a variable override.
  #
  # !important throughout, for the same reason contentTokens needs it:
  # userChrome.css is a USER sheet and popup.css is an AUTHOR sheet, and both
  # selectors land on the same specificity (:is() takes its most specific
  # argument = one element, :where() contributes nothing, so popup.css is
  # (0,0,1) exactly like `menupopup, panel`). A specificity tie across origins
  # is decided by origin, and author beats user -- verified by shipping this
  # block without !important, where --panel-background-color stayed `Menu`.
  #
  # This is why chromeVars gets away with plain declarations and this does not:
  # nothing in the stock chrome declares --lwt-*/--arrowpanel-*, so there is no
  # competing author rule to lose to.
  menuVars = c: ''
    menupopup,
    panel {
      --panel-background-color: ${css c.base01} !important;
      --panel-text-color: ${css c.base05} !important;
      --panel-separator-color: ${css c.base02} !important;
    }

    /* :where() keeps specificity at the bare element selector, so a more
       specific stock rule for a particular menu still wins. */
    menupopup :is(menu, menuitem):where([_moz-menuactive="true"]:not([disabled="true"])) {
      background-color: ${css c.base03} !important;
      color: ${css c.base06} !important;
    }
  '';

  # The theme API's color keys, per
  # developer.mozilla.org/docs/Mozilla/Add-ons/WebExtensions/manifest.json/theme
  themeApiColors = c: {
    frame = rgba c.base00;
    frame_inactive = rgba c.base01;

    tab_background_text = rgba c.base04;
    tab_selected = rgba c.base01;
    tab_text = rgba c.base05;
    tab_line = rgba c.base0D;
    tab_loading = rgba c.base0C;

    toolbar = rgba c.base01;
    toolbar_text = rgba c.base05;
    toolbar_top_separator = rgba c.base02;
    toolbar_bottom_separator = rgba c.base02;
    toolbar_vertical_separator = rgba c.base03;

    toolbar_field = rgba c.base02;
    toolbar_field_text = rgba c.base05;
    toolbar_field_border = rgba c.base03;
    toolbar_field_focus = rgba c.base01;
    toolbar_field_text_focus = rgba c.base06;
    toolbar_field_border_focus = rgba c.base0D;
    toolbar_field_highlight = rgba c.base02;
    toolbar_field_highlight_text = rgba c.base07;

    button_background_hover = rgba c.base02;
    button_background_active = rgba c.base03;

    icons = rgba c.base05;
    icons_attention = rgba c.base09;

    popup = rgba c.base01;
    popup_text = rgba c.base05;
    popup_border = rgba c.base03;
    popup_highlight = rgba c.base02;
    popup_highlight_text = rgba c.base06;

    sidebar = rgba c.base00;
    sidebar_text = rgba c.base05;
    sidebar_border = rgba c.base03;
    sidebar_highlight = rgba c.base02;
    sidebar_highlight_text = rgba c.base06;

    ntp_background = rgba c.base00;
    ntp_card_background = rgba c.base01;
    ntp_text = rgba c.base05;
  };

  # Firefox 154's in-content pages (about:config, about:addons, about:preferences,
  # the whole moz-* widget set) are themed by a design-token system under
  # chrome/toolkit/skin/classic/global/design-system/, not by the --lwt-*
  # variables the chrome uses. That is why those pages stayed violet: the "nova"
  # token layer defines --color-accent-primary and --text-color from a violet
  # ramp (tokens-platform.css:231, tokens-shared.css:1063) and userChrome.css
  # never reaches content documents.
  #
  # The graph is well-factored -- most tokens derive from a small root set via
  # var(), so redefining the roots recolors everything downstream. The violet
  # primitives are overridden too, to catch tokens referencing the ramp directly.
  #
  # Every declaration is !important, which is load-bearing, not belt-and-braces.
  # The tokens are declared inside @layers (tokens-foundation,
  # tokens-browser-theme-nova, ...) and unlayered does beat layered -- but only
  # *within one origin*. userContent.css is a USER sheet while chrome://newtab
  # and chrome://global/skin/design-system are AUTHOR sheets, and for normal
  # declarations author beats user outright; layers never enter into it.
  # !important inverts the origin order, which is the only thing that wins here.
  #
  # Verified over the debug bridge: two otherwise identical user sheets, the
  # !important one won and the plain one lost to Firefox's violet
  # (light-dark(#764EDD, #B89CFF)) the moment the important sheet was dropped.
  #
  # light-dark() is used rather than a media query so each token follows the
  # page's own color-scheme, which is what the stock tokens do.
  contentTokens =
    let
      # light-dark() takes the light value first. !important is applied here so
      # every token below carries it without repeating it 40 times.
      ld = lightHex: darkHex: "light-dark(${css lightHex}, ${css darkHex}) !important";
    in
    ''
      :root {
        /* Surfaces */
        --background-color-canvas: ${ld l.base00 d.base00};
        --background-color-box: ${ld l.base01 d.base01};
        --background-color-box-info: ${ld l.base02 d.base02};
        --table-row-background-color: ${ld l.base00 d.base00};
        --table-row-background-color-alternate: ${ld l.base01 d.base01};
        --panel-background-color: ${ld l.base01 d.base01};
        --toolbar-background-color: ${ld l.base01 d.base01};

        /* New tab card surfaces. activity-stream.css hardcodes these as
           literal hex under :root[lwt-newtab-brighttext] rather than deriving
           them from a design token, so the overrides above never reach them --
           they have to be named directly. Drives the search bar background
           (via --content-search-handoff-ui-background-color), the weather
           widget, and the top-site tiles. */
        --newtab-background-color-secondary: ${ld l.base01 d.base01};
        --newtab-background-card: ${ld l.base01 d.base01};
        --newtab-weather-background-color: ${ld l.base01 d.base01};

        /* Text */
        --text-color: ${ld l.base05 d.base05};
        --text-color-deemphasized: ${ld l.base04 d.base04};
        --text-color-error: ${ld l.base08 d.base08};
        --panel-text-color: ${ld l.base05 d.base05};
        --toolbar-field-text-color: ${ld l.base05 d.base05};
        --toolbar-field-text-color-focus: ${ld l.base06 d.base06};

        /* Accent -- the violet that motivated all this */
        --color-accent-primary: ${ld l.base0D d.base0D};
        --color-accent-primary-hover: ${ld l.base0C d.base0C};
        --color-accent-primary-active: ${ld l.base0C d.base0C};
        --color-accent-primary-selected: ${ld l.base0D d.base0D};
        --color-accent-attention: ${ld l.base0B d.base0B};
        --link-color: ${ld l.base0D d.base0D};
        --link-color-hover: ${ld l.base0C d.base0C};
        --link-color-visited: ${ld l.base0E d.base0E};
        --focus-outline-color: ${ld l.base0D d.base0D};

        /* Borders */
        --border-color: ${ld l.base03 d.base03};
        --border-color-card: ${ld l.base02 d.base02};
        --border-color-interactive: ${ld l.base03 d.base03};
        --panel-border-color: ${ld l.base03 d.base03};
        --toolbar-field-border-color: ${ld l.base03 d.base03};
        --info-bar-border-color: ${ld l.base03 d.base03};

        /* Buttons. Primary derives from --color-accent-primary above; these
           are the neutral variants, which reference the violet ramp directly. */
        --button-background-color: ${ld l.base02 d.base02};
        --button-background-color-hover: ${ld l.base03 d.base03};
        --button-background-color-active: ${ld l.base04 d.base04};
        --button-text-color: ${ld l.base05 d.base05};
        --button-text-color-primary: ${ld l.base00 d.base00};

        /* Semantic fills */
        --background-color-information: ${ld l.base02 d.base02};
        --icon-color-information: ${ld l.base0D d.base0D};
        --icon-color-success: ${ld l.base0B d.base0B};
        --icon-color-warning: ${ld l.base0A d.base0A};
        --icon-color-critical: ${ld l.base08 d.base08};
        --icon-color-accent-primary-desaturated: ${ld l.base0D d.base0D};

        /* The violet primitives themselves. Any token still referencing the
           ramp directly resolves through these instead of Firefox's violet. */
        --color-violet-5: ${ld l.base01 d.base01};
        --color-violet-30: ${ld l.base0E d.base0E};
        --color-violet-40: ${ld l.base0E d.base0E};
        --color-violet-50: ${ld l.base0D d.base0D};
        --color-violet-60: ${ld l.base0D d.base0D};
        --color-violet-70: ${ld l.base0C d.base0C};
        --color-violet-desaturated-0: ${ld l.base07 d.base07};
        --color-violet-desaturated-10: ${ld l.base06 d.base06};
        --color-violet-desaturated-20: ${ld l.base02 d.base02};
        --color-violet-desaturated-30: ${ld l.base03 d.base03};
        --color-violet-desaturated-40: ${ld l.base03 d.base03};
        --color-violet-desaturated-50: ${ld l.base04 d.base04};
        --color-violet-desaturated-70: ${ld l.base05 d.base05};
        --color-violet-desaturated-90: ${ld l.base05 d.base05};
      }
    '';

  d = theme.dark;
  l = theme.light;

  # Sidebery runs in the extension's content process, where the chrome's
  # --lwt-* properties are not visible, so the palette has to be handed to it
  # explicitly. The stylesheet is stored as text in extension storage (see
  # sidebarCSS in default.nix), so this is a plain string prepend rather than
  # an @import.
  #
  # Dark only: Sidebery's panel is themed against the chrome, which this module
  # pins to the dark palette.
  sidebarPalette = ''
    :root {
    ${builtins.concatStringsSep "\n" (
      map (n: "  --neo-base${n}: ${css d."base${n}"};") [
        "00" "01" "02" "03" "04" "05" "06" "07"
        "08" "09" "0A" "0B" "0C" "0D" "0E" "0F"
      ]
    )}
    }
  '';
in
{
  # Content-area colors. These are global rather than per-scheme; Firefox picks
  # the `.dark` variant itself when the content color scheme is dark, so both
  # halves are supplied.
  settings = {
    "browser.display.background_color" = css l.base00;
    "browser.display.background_color.dark" = css d.base00;
    "browser.display.foreground_color" = css l.base05;
    "browser.display.foreground_color.dark" = css d.base05;

    "browser.anchor_color" = css l.base0D;
    "browser.anchor_color.dark" = css d.base0D;
    "browser.active_color" = css l.base0E;
    "browser.active_color.dark" = css d.base0E;
    "browser.visited_color" = css l.base0E;
    "browser.visited_color.dark" = css d.base0F;

    "editor.background_color" = css d.base01;

    "browser.newtabpage.activity-stream.newNewtabExperience.colors" =
      builtins.concatStringsSep "," (
        map css [
          d.base08
          d.base09
          d.base0A
          d.base0B
          d.base0C
          d.base0D
          d.base0E
        ]
      );

    "pdfjs.highlightEditorColors" = builtins.concatStringsSep "," [
      "yellow=${css d.base0A}"
      "green=${css d.base0B}"
      "blue=${css d.base0D}"
      "pink=${css d.base0E}"
      "red=${css d.base08}"
    ];
  };

  # Prepended to userChrome.css. :root carries the dark palette by default and
  # the light one under prefers-color-scheme, so the chrome follows the system.
  # Firefox resolves that media query against its own chrome color scheme, which
  # ui.systemUsesDarkTheme / the active built-in theme drive.
  userChrome = ''
    :root {
    ${chromeVars d}
    }

    ${menuVars d}

    @media (prefers-color-scheme: light) {
      :root {
    ${chromeVars l}
      }

    ${menuVars l}
    }

    ${contentTokens}
  '';

  # userContent.css -- in-content pages (about:config, about:addons,
  # about:preferences, about:profiles, the error pages). The design tokens are
  # the only thing that colors these; --lwt-* does not apply here.
  #
  # Wrapped in @-moz-document url-prefix("about:") so this only touches
  # Firefox's own about: pages, not arbitrary web content -- userContent.css
  # is otherwise a blanket sheet applied to every document, real websites
  # included. Requires layout.css.moz-document.content.enabled (set in
  # default.nix's settings block); that pref is off by default, and without
  # it this whole block is silently dropped.
  userContent = ''
    @-moz-document url-prefix("about:") {
      ${contentTokens}
    }
  '';

  # Sidebery's in-panel stylesheet, with the palette prepended so the CSS can
  # reference --neo-base00..0F instead of hardcoding hex.
  sidebarCSS = sidebarPalette + builtins.readFile ./chrome/CSS/sidebery.css;

  # firefox-color's stored theme. Same colors as the chrome CSS, routed through
  # the official theme API -- which reaches a few surfaces (notably the new tab
  # page) that userChrome.css cannot style.
  colorTheme = {
    firstRunDone = true;
    theme = {
      colors = themeApiColors d;
      images = {
        additional_backgrounds = [ ];
        custom_backgrounds = [ ];
      };
      title = "firefox-neo";
    };
  };
}
