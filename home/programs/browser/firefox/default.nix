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
            # Essential
            ublock-origin
            bitwarden
            #onepassword-password-manager
            sidebery
            tridactyl
            # Privacy
            smart-referer
            cookie-autodelete
            user-agent-string-switcher

            firefox-color
          ];
          # to configure extensions:
          # 1. url: about:debugging#/runtime/this-firefox
          # 2. find extension -> click "Inspect"
          # 3. Go to Storage tab -> Extension Storage

          # sidebery:
          settings."3c078156-979c-498b-8990-85f7987dd929" = {
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
            colors = {
              # TODO: hexToRgb, format needs to change alpha to a. in a let-in function
              # color-lib.hexToRgb theme.dark.base00

              # background
              toolbar = {
                r = 7;
                g = 50;
                b = 84;
              };
              toolbar_text = {
                r = 67;
                g = 194;
                b = 218;
              };

              frame = {
                r = 14;
                g = 41;
                b = 65;
              };
              frame_inactive = {
                r = 250;
                g = 255;
                b = 0;
              };

              tab_background_text = {
                r = 24;
                g = 156;
                b = 180;
              };
              toolbar_field = {
                r = 38;
                g = 72;
                b = 102;
              };
              toolbar_field_text = {
                r = 67;
                g = 194;
                b = 218;
              };
              tab_line = {
                r = 67;
                g = 194;
                b = 218;
              };

              # background
              popup = {
                r = 7;
                g = 50;
                b = 84;
              };
              popup_text = {
                r = 24;
                g = 156;
                b = 180;
              };
              popup_border = {
                r = 149;
                g = 0;
                b = 40;
              };
              popup_highlight_text = {
                r = 153;
                g = 91;
                b = 0;
              };
              popup_highlight = {
                r = 27;
                g = 164;
                b = 0;
              };

              # toggle color
              button_background_active = {
                r = 255;
                g = 0;
                b = 0;
              };
              # hover color
              button_background_hover = {
                r = 255;
                g = 147;
                b = 0;
              };

              # visual download-ed indication/ interaction indication that something changed.
              icons_attention = {
                r = 20;
                g = 255;
                b = 0;
              };
              # top bar buttons color; reload; etc.
              icons = {
                r = 0;
                g = 255;
                b = 250;
              };
              # not sure:
              ntp_background = {
                r = 44;
                g = 0;
                b = 255;
              };
              ntp_text = {
                r = 250;
                g = 0;
                b = 255;
              };

              # sideberry / treeStyle tabs panel
              sidebar_border = {
                r = 0;
                g = 155;
                b = 146;
              };
              sidebar_highlight_text = {
                r = 13;
                g = 0;
                b = 166;
              };
              sidebar_highlight = {
                r = 152;
                g = 0;
                b = 170;
              };
              sidebar_text = {
                r = 122;
                g = 0;
                b = 2;
              };
            };
            images = {
              additional_backgrounds = [];
              custom_backgrounds = [];
            };
            title = "002";
          };
        };

        userChrome =
          import ./userChrome.nix {inherit theme color-lib firefox-csshacks;};
        search = import ./searchEngines {inherit pkgs lib;};
      };

      "minimal" = {
        isDefault = false;
        id = 1;
        name = "minimal";

        # Extensions for the minimal profile
        extensions.packages = with addons; [
          # Essential
          ublock-origin
          bitwarden
          sidebery
          tridactyl
        ];

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
        userChrome = import ./userChrome.nix {
          inherit theme color-lib firefox-csshacks;
        };
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
