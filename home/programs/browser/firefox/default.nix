{
  inputs,
  pkgs,
  theme,
  lib,
  color-lib,
  config,
  ...
}: let
  addons = inputs.firefox-addons.packages.${pkgs.system};

  firefox-csshacks = pkgs.stdenv.mkDerivation {
    name = "patched-firefox-csshacks";
    src = inputs.firefox-csshacks;
    installPhase = ''
      cp -r . $out
    '';
  };
in rec {
  home.sessionVariables = {BROWSER = "firefox";};

  programs.firefox = {
    enable = true;
    profiles = {
      "main" = {
        isDefault = true;
        id = 0;
        name = "main";

        # Extensions for the main profile
        extensions = {
          force = true;
          packages = with addons; [
            sidebery

            ublock-origin
            bitwarden
            # onepassword-password-manager
            # tridactyl
            # Privacy
            smart-referer
            # cookie-autodelete
            # user-agent-string-switcher

            dearrow
            fake-filler
            imagus-mod
            sponsorblock
            violentmonkey

            firefox-color
          ];
          # to configure extensions:
          # 1. url: about:debugging#/runtime/this-firefox
          # 2. find extension -> click "Inspect"
          # 3. Go to Storage tab -> Extension Storage

          # sidebery:
          settings."{3c078156-979c-498b-8990-85f7987dd929}" = {
            force = true;
            settings = {
              sidebarCSS = ''
                #root.root {
                  --nav-btn-width: 37px;
                  --nav-btn-height: 37px;
                  --tabs-height: 28px;
                  --bookmarks-folder-height: 32px;
                  --bookmarks-bookmark-height: 30px;

                  /* Clean technical sans-serif fonts - NO SERIF! */
                  --tabs-count-font: 0.5625rem "JetBrains Mono", "Fira Code", "Source Code Pro", "Roboto Mono", monospace;
                  --tabs-font: 0.9375rem "JetBrains Mono", "Fira Code", "Source Code Pro", "Roboto Mono", monospace;
                  --ctx-menu-font: 0.875rem "JetBrains Mono", "Fira Code", "Source Code Pro", "Roboto Mono", monospace;
                  --bookmarks-bookmark-font: 0.9375rem "JetBrains Mono", "Fira Code", "Source Code Pro", "Roboto Mono", monospace;
                  --bookmarks-folder-font: 0.9375rem "JetBrains Mono", "Fira Code", "Source Code Pro", "Roboto Mono", monospace;

                  /* Alternative clean geometric sans-serif option: */
                  /*
                  --tabs-count-font: 0.5625rem "Helvetica Neue", "Arial", "Roboto", sans-serif;
                  --tabs-font: 0.9375rem "Helvetica Neue", "Arial", "Roboto", sans-serif;
                  --ctx-menu-font: 0.875rem "Helvetica Neue", "Arial", "Roboto", sans-serif;
                  --bookmarks-bookmark-font: 0.9375rem "Helvetica Neue", "Arial", "Roboto", sans-serif;
                  --bookmarks-folder-font: 0.9375rem "Helvetica Neue", "Arial", "Roboto", sans-serif;
                  */

                  --tabs-lvl-opacity: 0.16;
                  --button-n-tab-colour: rgb(0, 0, 0, 0);
                  --button-tab-color: rgba(0, 0, 0, 0);
                  --transition-duration: 0.2s;
                  --transition-ease: ease;
                  --tabs-lvl-color: rgba(128, 128, 128, var(--tabs-lvl-opacity, 0.16));
                }

                /* Make text super crisp and clean */
                * {
                  -webkit-font-smoothing: antialiased;
                  -moz-osx-font-smoothing: grayscale;
                  text-rendering: optimizeLegibility;
                  font-variant-numeric: tabular-nums;
                  letter-spacing: -0.005em; /* Slightly tighter for cleaner look */
                }

                /* Ensure consistent sans-serif rendering */
                .Tab .title,
                .BookmarkNode .title,
                .nav-item {
                  font-family: inherit;
                  font-weight: 400;
                }

                /* Rest of your CSS stays the same... */
                .TabsPanel,
                .bookmarks-tree {
                  padding-left: 5px;
                  padding-right: 4px;
                  transition: padding var(--transition-duration) var(--transition-ease);
                }

                .NavigationBar,
                .nav-item,
                .static-btns,
                .main-items > .nav-item {
                  transition: none !important;
                }

                #root:not(.NavigationBar),
                .TabsPanel,
                .bookmarks-tree,
                .close,
                .BookmarkNode > .body::before,
                .BookmarkNode {
                  transition: all var(--transition-duration) var(--transition-ease);
                }

                .Tab {
                  transition: none !important;
                }

                .ctx {
                  box-shadow: 0 1px 10px 1px var(--color);
                  transition: box-shadow var(--transition-duration) var(--transition-ease);
                }

                .Tab[data-audible="true"] .audio {
                  height: 15px;
                  width: 15px;
                  top: 0px;
                  left: 14px;
                  border-radius: 50%;
                  transition: all var(--transition-duration) var(--transition-ease);
                }

                .Tab[data-audible="true"] .t-box {
                  --audio-btn-offset: 0px;
                  transition: all var(--transition-duration) var(--transition-ease);
                }

                .nav-item:hover {
                  background-color: rgba(255, 255, 255, 0.1);
                }

                .main-items > .nav-item[data-active="true"] {
                  transform: scale(1.05);
                }

                .Tab > .body {
                  position: relative;
                }

                @media screen and (max-width: 50px) {
                  .Tab .t-box {
                    display: none;
                  }

                  .Tab .body::after {
                    display: none !important;
                  }

                  .Tab[data-parent="true"][data-folded="true"] .exp {
                    display: none !important;
                  }
                }

                @media screen and (max-width: 55px) {
                  #root {
                    --tabs-indent: 0px !important;
                    --bookmarks-indent: 0px !important;
                  }

                  .TabsPanel {
                    padding-left: 3px;
                    padding-right: 3px;
                  }

                  .static-btns {
                    visibility: collapse;
                  }

                  .main-items > .nav-item[data-active="true"] {
                    opacity: 100 !important;
                    transform: initial !important;
                  }

                  .BookmarkNode > .body::before {
                    left: -2px;
                    width: calc(100% + 0.5em);
                  }

                  .close {
                    display: none !important;
                  }
                }

                .Tab[data-colorized="true"] .color-layer {
                  background-color: transparent !important;
                  background-image: radial-gradient(
                    circle 10px at 15px center,
                    var(--tab-color, rgba(0, 0, 0, 1)) 80%,
                    rgba(0, 0, 0, 0) 100%
                  );
                  background-repeat: no-repeat;
                }
              '';
              settings = {
                nativeScrollbars = false;
                nativeScrollbarsThin = false;
                nativeScrollbarsLeft = false;
                selWinScreenshots = false;
                updateSidebarTitle = true;
                markWindow = false;
                markWindowPreface = "[Sidebery] ";
                ctxMenuNative = false;
                ctxMenuRenderInact = true;
                ctxMenuRenderIcons = true;
                ctxMenuIgnoreContainers = "";
                navBarLayout = "horizontal";
                navBarInline = true;
                navBarSide = "left";
                hideAddBtn = false;
                hideSettingsBtn = false;
                navBtnCount = true;
                hideEmptyPanels = true;
                hideDiscardedTabPanels = false;
                navActTabsPanelLeftClickAction = "none";
                navActBookmarksPanelLeftClickAction = "none";
                navTabsPanelMidClickAction = "discard";
                navBookmarksPanelMidClickAction = "none";
                navSwitchPanelsWheel = true;
                subPanelRecentlyClosedBar = true;
                subPanelBookmarks = true;
                subPanelHistory = true;
                subPanelSync = false;
                groupLayout = "grid";
                containersSortByName = false;
                skipEmptyPanels = false;
                dndTabAct = false;
                dndTabActDelay = 750;
                dndTabActMod = "none";
                dndExp = "none";
                dndExpDelay = 750;
                dndExpMod = "shift";
                dndOutside = "win";
                dndActTabFromLink = true;
                dndActSearchTab = true;
                dndMoveTabs = true;
                dndMoveBookmarks = false;
                searchBarMode = "static";
                searchPanelSwitch = "same_type";
                searchBookmarksShortcut = "";
                searchHistoryShortcut = "";
                warnOnMultiTabClose = "none";
                activateLastTabOnPanelSwitching = true;
                activateLastTabOnPanelSwitchingLoadedOnly = true;
                switchPanelAfterSwitchingTab = "always";
                tabRmBtn = "hover";
                activateAfterClosing = "next";
                activateAfterClosingStayInPanel = false;
                activateAfterClosingGlobal = false;
                activateAfterClosingNoFolded = true;
                activateAfterClosingNoDiscarded = true;
                askNewBookmarkPlace = true;
                tabsRmUndoNote = false;
                tabsUnreadMark = false;
                tabsUpdateMark = "all";
                tabsUpdateMarkFirst = true;
                tabsReloadLimit = 10;
                tabsReloadLimitNotif = true;
                showNewTabBtns = true;
                newTabBarPosition = "after_tabs";
                tabsPanelSwitchActMove = false;
                tabsPanelSwitchActMoveAuto = true;
                tabsUrlInTooltip = "full";
                newTabCtxReopen = false;
                tabWarmupOnHover = true;
                tabSwitchDelay = 0;
                forceDiscard = true;
                moveNewTabPin = "start";
                moveNewTabParent = "first_child";
                moveNewTabParentActPanel = false;
                moveNewTab = "before";
                moveNewTabActivePin = "start";
                pinnedTabsPosition = "top";
                pinnedTabsList = true;
                pinnedAutoGroup = true;
                pinnedNoUnload = false;
                pinnedForcedDiscard = false;
                tabsTree = true;
                groupOnOpen = true;
                tabsTreeLimit = "none";
                autoFoldTabs = true;
                autoFoldTabsExcept = 2;
                autoExpandTabs = true;
                autoExpandTabsOnNew = true;
                rmChildTabs = "folded";
                tabsLvlDots = true;
                discardFolded = true;
                discardFoldedDelay = 60;
                discardFoldedDelayUnit = "min";
                tabsTreeBookmarks = true;
                treeRmOutdent = "first_child";
                autoGroupOnClose = true;
                autoGroupOnClose0Lvl = true;
                autoGroupOnCloseMouseOnly = true;
                ignoreFoldedParent = false;
                showNewGroupConf = true;
                sortGroupsFirst = true;
                colorizeTabs = true;
                colorizeTabsSrc = "domain";
                colorizeTabsBranches = false;
                colorizeTabsBranchesSrc = "domain";
                inheritCustomColor = true;
                previewTabs = false;
                previewTabsMode = "i";
                previewTabsPageModeFallback = "w";
                previewTabsInlineHeight = 70;
                previewTabsPopupWidth = 280;
                previewTabsTitle = 2;
                previewTabsUrl = 1;
                previewTabsSide = "right";
                previewTabsDelay = 500;
                previewTabsFollowMouse = true;
                previewTabsWinOffsetY = 36;
                previewTabsWinOffsetX = 6;
                previewTabsInPageOffsetY = 0;
                previewTabsInPageOffsetX = 0;
                previewTabsCropRight = 0;
                hideInact = false;
                hideFoldedTabs = false;
                hideFoldedParent = "none";
                nativeHighlight = false;
                warnOnMultiBookmarkDelete = "collapsed";
                autoCloseBookmarks = false;
                autoRemoveOther = false;
                highlightOpenBookmarks = false;
                activateOpenBookmarkTab = false;
                showBookmarkLen = true;
                bookmarksRmUndoNote = true;
                loadBookmarksOnDemand = true;
                pinOpenedBookmarksFolder = true;
                oldBookmarksAfterSave = "ask";
                loadHistoryOnDemand = true;
                fontSize = "m";
                animations = true;
                animationSpeed = "norm";
                theme = "proton";
                density = "default";
                colorScheme = "ff";
                snapNotify = true;
                snapExcludePrivate = false;
                snapInterval = 1;
                snapIntervalUnit = "hr";
                snapLimit = 0;
                snapLimitUnit = "snap";
                snapAutoExport = true;
                snapAutoExportType = "json";
                snapAutoExportPath = "Sidebery/snapshot-%Y.%M.%D-%h.%m.%s";
                snapMdFullTree = false;
                hScrollAction = "switch_panels";
                onePanelSwitchPerScroll = true;
                wheelAccumulationX = true;
                wheelAccumulationY = true;
                navSwitchPanelsDelay = 128;
                scrollThroughTabs = "none";
                scrollThroughVisibleTabs = true;
                scrollThroughTabsSkipDiscarded = true;
                scrollThroughTabsExceptOverflow = true;
                scrollThroughTabsCyclic = false;
                scrollThroughTabsScrollArea = 0;
                autoMenuMultiSel = true;
                multipleMiddleClose = false;
                longClickDelay = 500;
                wheelThreshold = false;
                wheelThresholdX = 100000;
                wheelThresholdY = 60;
                tabDoubleClick = "none";
                tabsSecondClickActPrev = true;
                tabsSecondClickActPrevPanelOnly = false;
                tabsSecondClickActPrevNoUnload = false;
                shiftSelAct = true;
                activateOnMouseUp = false;
                tabLongLeftClick = "dup_child";
                tabLongRightClick = "none";
                tabMiddleClick = "close";
                tabPinnedMiddleClick = "discard";
                tabMiddleClickCtrl = "discard";
                tabMiddleClickShift = "duplicate";
                tabCloseMiddleClick = "close";
                tabsPanelLeftClickAction = "none";
                tabsPanelDoubleClickAction = "tab";
                tabsPanelRightClickAction = "menu";
                tabsPanelMiddleClickAction = "tab";
                newTabMiddleClickAction = "new_child";
                bookmarksLeftClickAction = "open_in_act";
                bookmarksLeftClickActivate = false;
                bookmarksLeftClickPos = "default";
                bookmarksMidClickAction = "open_in_new";
                bookmarksMidClickActivate = false;
                bookmarksMidClickRemove = false;
                bookmarksMidClickPos = "default";
                historyLeftClickAction = "open_in_act";
                historyLeftClickActivate = false;
                historyLeftClickPos = "default";
                historyMidClickAction = "open_in_new";
                historyMidClickActivate = false;
                historyMidClickPos = "default";
                syncName = "";
                syncUseFirefox = true;
                syncUseGoogleDrive = false;
                syncUseGoogleDriveApi = false;
                syncUseGoogleDriveApiClientId = "";
                syncSaveSettings = true;
                syncSaveCtxMenu = true;
                syncSaveStyles = true;
                syncSaveKeybindings = true;
                selectActiveTabFirst = true;
                selectCyclic = false;
              };
            };
          };
          # https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/theme#colors
          settings."FirefoxColor@mozilla.com".settings = {
            firstRunDone = true;
            theme = let
              c = theme.dark;

              hexToRgba = hex: let
                round = x: builtins.floor (x + 0.5);
                rgb = color-lib.hexToRgb hex;
              in {
                r = round (rgb.r * 256);
                g = round (rgb.g * 256);
                b = round (rgb.b * 256); # int
                a = rgb.alpha; # 0-1
              };
            in {
              colors = {
                ### FRAME / HEADER AREA
                # Main browser frame background (header area behind tabs)
                frame = hexToRgba c.base00;

                # Frame color when window is inactive/unfocused
                # Using base01 for subtle differentiation
                frame_inactive = hexToRgba c.base01;

                ### TABS
                # Text color for inactive/background tabs
                tab_background_text = hexToRgba c.base04;

                # Background color of the selected/active tab
                # Using base01 to lift it from frame
                tab_selected = hexToRgba c.base01;

                # Text color for the selected/active tab
                tab_text = hexToRgba c.base05;

                # Accent line on selected tab (the colored strip)
                # Using accent color (blue) for visual pop
                tab_line = hexToRgba c.base0D;

                # Tab loading indicator color
                tab_loading = hexToRgba c.base0C; # cyan for loading animation

                ### TOOLBAR (Navigation bar, bookmarks bar)

                # Toolbar background color
                toolbar = hexToRgba c.base01;

                # Toolbar text and bookmark text color
                # Also affects toolbar icons if 'icons' not set
                toolbar_text = hexToRgba c.base05;

                # Separator line above toolbar
                toolbar_top_separator = hexToRgba c.base02;

                # Separator line below toolbar (between toolbar and content)
                toolbar_bottom_separator = hexToRgba c.base02;

                # Vertical separators in toolbar/bookmarks bar
                toolbar_vertical_separator = hexToRgba c.base03;

                ### URL BAR / INPUT FIELDS

                # URL bar background (unfocused)
                toolbar_field = hexToRgba c.base02;

                # URL bar text (unfocused)
                toolbar_field_text = hexToRgba c.base05;

                # URL bar border (unfocused)
                toolbar_field_border = hexToRgba c.base03;

                # URL bar background (focused)
                # Slightly lighter than unfocused for visual feedback
                toolbar_field_focus = hexToRgba c.base01;

                # URL bar text (focused)
                toolbar_field_text_focus = hexToRgba c.base06;

                # URL bar border (focused) - accent color for clear focus indication
                toolbar_field_border_focus = hexToRgba c.base0D;

                # Selected/highlighted text background in URL bar
                # DERIVED: Consider using base0D at ~30% opacity for better selection visibility
                toolbar_field_highlight = hexToRgba c.base02;

                # Selected/highlighted text color in URL bar
                toolbar_field_highlight_text = hexToRgba c.base07;

                ### BUTTONS

                # Toolbar button background on hover
                button_background_hover = hexToRgba c.base02;

                # Toolbar button background when pressed/active
                button_background_active = hexToRgba c.base03;

                ### ICONS

                # Toolbar icons color (reload, home, menu, ethexToRgba c.)
                icons = hexToRgba c.base05;

                # Icons in attention state (starred bookmark, download complete)
                # Using warm accent for attention-grabbing
                icons_attention = hexToRgba c.base09; # orange for attention

                ### POPUPS (URL bar dropdown, menus, panels)

                # Popup background
                popup = hexToRgba c.base01;

                # Popup text color
                popup_text = hexToRgba c.base05;

                # Popup border color
                popup_border = hexToRgba c.base03;

                # Background of highlighted/selected item in popup
                popup_highlight = hexToRgba c.base02;

                # Text color of highlighted/selected item in popup
                popup_highlight_text = hexToRgba c.base06;

                ### SIDEBAR (Bookmarks, History, Synced tabs)

                # Sidebar background
                sidebar = hexToRgba c.base00;

                # Sidebar text color
                sidebar_text = hexToRgba c.base05;

                # Sidebar border/splitter color
                sidebar_border = hexToRgba c.base03;

                # Sidebar highlighted row background
                sidebar_highlight = hexToRgba c.base02;

                # Sidebar highlighted row text
                sidebar_highlight_text = hexToRgba c.base06;

                ### NEW TAB PAGE

                # New tab page background
                ntp_background = hexToRgba c.base00;

                # New tab page card backgrounds (search box, shortcuts)
                ntp_card_background = hexToRgba c.base01;

                # New tab page text color
                ntp_text = hexToRgba c.base05;
              };
              images = {
                additional_backgrounds = [];
                custom_backgrounds = [];
              };
              title = "002";
            };
          };
        };

        userChrome = let
          chrome = import ./chrome.nix {inherit pkgs lib;} {inherit firefox-csshacks;};
        in
          chrome.mkUserChrome [
            (chrome.autohide_sidebar.overrideAttrs (old: {
              postPatch = ''
                substituteInPlace source.css \
                  --replace-fail "--uc-sidebar-hover-width: 210px" "--uc-sidebar-hover-width: 25vw" \
                  --replace-fail "--uc-autohide-sidebar-delay: 600ms" "--uc-autohide-sidebar-delay: 100ms" \
                  --replace-fail "--uc-autohide-transition-duration: 115ms" "--uc-autohide-transition-duration: 200ms" \
                  --replace-fail "--uc-autohide-transition-type: linear" "--uc-autohide-transition-type: ease-in-out"
                  # --replace-fail "--uc-sidebar-width: 40px" "--uc-sidebar-width: 38px" \
              '';
              postInstall = ''
                cat >> $out << 'EOF'
                #sidebar-box { z-index: 3 !important; }
                #sidebar-header { display: none; }
                EOF
              '';
            }))

            chrome.autohide_bookmarks_toolbar
            chrome.auto_devtools_theme_for_rdm
            chrome.hide_tabs_toolbar_v2

            (chrome.mkCustom ''
              :root {
                --panel-width: 100vw;
                --panel-hide-offset: -30px;
                --opacity-when-hidden: 0.0;
              }

              #TabsToolbar { visibility: collapse; }
              .titlebar-buttonbox-container,
              .titlebar-spacer[type="post-tabs"] { display: none; }
            '')
          ];
        search = import ./searchEngines {inherit pkgs lib;};
      };

      "minimal" = {
        isDefault = false;
        id = 1;
        name = "minimal";

        # Extensions for the minimal profile
        extensions = {
          force = true;
          packages = with addons; [
            # Essential
            ublock-origin
            bitwarden
            sidebery
            tridactyl

            firefox-color
          ];
        };

        # Rest of minimal profile config...
        search = import ./searchEngines {inherit pkgs lib;};
      };

      "testing2" = {
        isDefault = false;
        id = 2;
        name = "testing2";

        settings =
          import ./settings/default.nix {inherit theme lib color-lib;};
        extensions.packages = with addons; [sidebery];
        userChrome = let
          chrome = import ./chrome.nix {inherit pkgs lib;} {inherit firefox-csshacks;};
        in
          chrome.mkUserChrome [
            (chrome.autohide_sidebar.overrideAttrs (old: {
              postPatch = ''
                substituteInPlace source.css \
                  --replace-fail "--uc-sidebar-width: 40px" "--uc-sidebar-width: 38px" \
                  --replace-fail "--uc-sidebar-hover-width: 210px" "--uc-sidebar-hover-width: 25vw" \
                  --replace-fail "--uc-autohide-sidebar-delay: 600ms" "--uc-autohide-sidebar-delay: 100ms" \
                  --replace-fail "--uc-autohide-transition-duration: 115ms" "--uc-autohide-transition-duration: 200ms" \
                  --replace-fail "--uc-autohide-transition-type: linear" "--uc-autohide-transition-type: ease-in-out"
              '';
              postInstall = ''
                cat >> $out << 'EOF'
                #sidebar-box { z-index: 3 !important; }
                #sidebar-header { display: none; }
                EOF
              '';
            }))

            chrome.autohide_bookmarks_toolbar
            chrome.auto_devtools_theme_for_rdm
            chrome.hide_tabs_toolbar_v2

            (chrome.mkCustom ''
              :root {
                --panel-width: 100vw;
                --panel-hide-offset: -30px;
                --opacity-when-hidden: 0.0;
              }

              #TabsToolbar { visibility: collapse; }
              .titlebar-buttonbox-container,
              .titlebar-spacer[type="post-tabs"] { display: none; }
            '')
          ];
      };

      "projection" = {
        isDefault = false;
        id = 3;
        name = "projection";

        settings =
          import ./settings/default.nix {inherit theme lib color-lib;};
        extensions.packages = with addons; [sidebery];
        userChrome = import ./userChrome-minimal.nix {
          inherit theme color-lib firefox-csshacks;
        };
      };
    };
  };

  # auto generate the desktop entries for each profile (Linux only)
  xdg.desktopEntries = lib.mkIf pkgs.stdenv.isLinux (let
    mkFirefoxDesktopEntry = profile: {
      name = "Firefox (${profile.name})";
      genericName = "Web Browser";
      exec = "${pkgs.firefox}/bin/firefox -P ${profile.name}";
      icon = "${pkgs.firefox}/lib/firefox/browser/chrome/icons/default/default128.png";
      type = "Application";
      categories = ["Network" "WebBrowser"];
      mimeType = ["text/html" "text/xml"];
    };
  in
    lib.mapAttrs (name: profile: mkFirefoxDesktopEntry profile)
    programs.firefox.profiles
    // {
      firefox-private = {
        name = "Firefox Private";
        genericName = "Web Browser";
        exec = "${pkgs.firefox}/bin/firefox --private-window";
        icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
        type = "Application";
        categories = ["Network" "WebBrowser"];
        mimeType = ["text/html" "text/xml"];
      };
    });
}
