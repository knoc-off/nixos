{
  theme,
  color-lib,
}: {
  # to configure extensions:
  # 1. url: about:debugging#/runtime/this-firefox
  # 2. find extension -> click "Inspect"
  # 3. Go to Storage tab -> Extension Storage

  "{3c078156-979c-498b-8990-85f7987dd929}" = {
    force = true;
    settings = {
      sidebarCSS = let
        tabDepthStyle = depth: hueRot: ''
          .Tab[data-lvl="${toString depth}"][data-colorized="true"][data-parent="true"] .color-layer {
            background-color: oklch(from var(--tab-color) 70% 0.25 calc(h + ${toString hueRot})) !important;
            height: 100%;
          }
          .Tab[data-lvl="${toString depth}"][data-colorized="true"][data-parent="true"][data-folded="true"] .color-layer {
            background-color: oklch(from var(--tab-color) 45% 0.12 calc(h + ${toString hueRot})) !important;
          }
          .Tab[data-lvl="${toString depth}"][data-colorized="true"]:not([data-parent="true"]) .color-layer {
            background-color: oklch(from var(--tab-color) 70% 0.25 calc(h + ${toString hueRot})) !important;
            height: 50%;
          }
        '';

        depthStyles = builtins.concatStringsSep "\n" (
          builtins.genList (i: tabDepthStyle i (i * 40)) 10
        );
      in ''
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
          /* Hide all text elements */
          .Tab .t-box,
          .Tab .close,
          .Tab .exp,
          .Tab .body::after,
          .BookmarkNode .title,
          .static-btns,
          .nav-item .label {
            display: none !important;
          }

          .main-items > .nav-item[data-active="true"] {
            opacity: 1 !important;
            transform: none !important;
          }

          /* Center the favicon/icon */
          .Tab .body {
            justify-content: center;
          }

          .Tab .fav {
            margin: 0 auto;
          }

          /* Remove indentation completely */
          #root {
            --tabs-indent: 0px !important;
            --bookmarks-indent: 0px !important;
          }

          /* Minimal padding */
          .TabsPanel {
            padding-left: 2px;
            padding-right: 2px;
          }

          /* Maybe shrink the color bar too */
          .Tab[data-colorized="true"] .color-layer {
            width: 2px !important;
          }

          /* Search bar: icon only, centered */
          .SearchBar .placeholder,
          .SearchBar .input {
            display: none !important;
          }

          .SearchBar {
            justify-content: center;
          }

          .SearchBar .search-icon {
            margin: 0 auto;
          }

          /* Notifications: icon only, centered */
          .notification .title,
          .notification .ctrls {
            display: none !important;
          }

          .notification {
            min-width: 32px;
            min-height: 32px;
            padding: 6px;
            display: flex;
            align-items: center;
            justify-content: center;
          }

          .notification .header {
            display: flex;
            align-items: center;
            justify-content: center;
            width: 100%;
            height: 100%;
          }

          .notification .icon {
            margin: 0;
            display: flex;
            align-items: center;
            justify-content: center;
          }

          .notification .icon svg {
            width: 18px;
            height: 18px;
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

        /* \/ These are semi redundant styles. \/ */

        /* Restyle the color layer as a left-side bar */
        .Tab[data-colorized="true"] .color-layer {
          width: 3px !important;
          height: 100%;
          border-radius: 2px 0 0 2px !important;
          background-color: oklch(from var(--tab-color) 70% 0.25 h) !important;
          opacity: 1 !important;
        }

        /* Collapsed/folded trees: dimmer color */
        .Tab[data-colorized="true"][data-folded="true"] .color-layer {
          background-color: oklch(from var(--tab-color) 45% 0.12 h) !important;
        }

        /* Non-parent tabs: half height */
        .Tab[data-colorized="true"]:not([data-parent="true"]) .color-layer {
          height: 50%;
        }

        /* Highlight unread tabs */
        .Tab[data-unread="true"] .title {
          font-weight: 600;
          opacity: 1;
        }

        .Tab[data-unread="true"]::after {
          content: "";
          position: absolute;
          top: 50%;
          right: 8px;
          transform: translateY(-50%);
          width: 6px;
          height: 6px;
          border-radius: 50%;
          background-color: var(--tab-color, #4a9eff);
          filter: saturate(2) brightness(1.5);
        }

        ${depthStyles}
      '';

      # Context menu configuration (matches Sidebery defaults from src/defaults/menu.ts)
      # Available tab options: undoRmTab, moveToNewWin, moveToWin, moveToPanel, moveToNewPanel,
      #   reopenInNewWin, reopenInWin, reopenInCtr, reopenInNewCtr, pin, reload, duplicate,
      #   bookmark, mute, discard, group, flatten, clearCookies, close, closeBranch,
      #   closeDescendants, closeTabsAbove, closeTabsBelow, closeOtherTabs, copyTabsUrls,
      #   copyTabsTitles, colorizeTab, editTabTitle, sortTabsByTitleAscending, etc.
      # Use "---" for separator
      contextMenu = {
        tabs = [
          {opts = ["undoRmTab" "mute" "reload" "bookmark"];}
          "separator-1"
          {
            name = "%menu.tab.move_to_sub_menu_name";
            opts = ["moveToNewWin" "moveToWin" "separator-5" "moveToPanel" "moveToNewPanel"];
          }
          {
            name = "%menu.tab.reopen_in_sub_menu_name";
            opts = ["reopenInNewWin" "reopenInWin" "separator-6" "reopenInCtr" "reopenInNewCtr"];
          }
          {
            name = "%menu.tab.colorize_";
            opts = ["colorizeTab"];
          }
          {
            name = "%menu.tab.sort_sub_menu_name";
            opts = [
              "sortTabsTreeByTitleAscending"
              "sortTabsTreeByTitleDescending"
              "sortTabsTreeByUrlAscending"
              "sortTabsTreeByUrlDescending"
              "sortTabsTreeByAccessTimeAscending"
              "sortTabsTreeByAccessTimeDescending"
              "separator-45654"
              "sortTabsByTitleAscending"
              "sortTabsByTitleDescending"
              "sortTabsByUrlAscending"
              "sortTabsByUrlDescending"
              "sortTabsByAccessTimeAscending"
              "sortTabsByAccessTimeDescending"
            ];
          }
          "separator-2"
          "pin"
          "duplicate"
          "discard"
          "copyTabsUrls"
          "copyTabsTitles"
          "editTabTitle"
          "separator-3"
          "group"
          "flatten"
          "separator-4"
          "urlConf"
          "close"
        ];
        tabsPanel = [
          {opts = ["undoRmTab" "muteAllAudibleTabs" "reloadTabs" "discardTabs"];}
          "separator-1224"
          {
            name = "%menu.tabs_panel.sort_all_sub_menu_name";
            opts = [
              "sortAllTabsByTitleAscending"
              "sortAllTabsByTitleDescending"
              "sortAllTabsByUrlAscending"
              "sortAllTabsByUrlDescending"
              "sortAllTabsByAccessTimeAscending"
              "sortAllTabsByAccessTimeDescending"
            ];
          }
          "separator-7"
          "selectAllTabs"
          "collapseInactiveBranches"
          "closeTabsDuplicates"
          "closeTabs"
          "separator-8"
          "bookmarkTabsPanel"
          "restoreFromBookmarks"
          "convertToBookmarksPanel"
          "separator-9"
          "openPanelConfig"
          "hidePanel"
          "removePanel"
        ];
        bookmarks = [
          {
            name = "%menu.bookmark.open_in_sub_menu_name";
            opts = [
              "openInNewWin"
              "openInNewPrivWin"
              "separator-9"
              "openInPanel"
              "openInNewPanel"
              "separator-10"
              "openInCtr"
            ];
          }
          {
            name = "%menu.bookmark.sort_sub_menu_name";
            opts = [
              "sortByNameAscending"
              "sortByNameDescending"
              "sortByLinkAscending"
              "sortByLinkDescending"
              "sortByTimeAscending"
              "sortByTimeDescending"
            ];
          }
          "separator-5"
          "createBookmark"
          "createFolder"
          "createSeparator"
          "separator-8"
          "openAsBookmarksPanel"
          "openAsTabsPanel"
          "separator-7"
          "copyBookmarksUrls"
          "copyBookmarksTitles"
          "moveBookmarksTo"
          "edit"
          "delete"
        ];
        bookmarksPanel = [
          "collapseAllFolders"
          "switchViewMode"
          "convertToTabsPanel"
          "separator-9"
          "unloadPanelType"
          "openPanelConfig"
          "hidePanel"
          "removePanel"
        ];
      };

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
        tabsUnreadMark = true;
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
        autoFoldTabs = false;
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
        colorizeTabsBranches = true;
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
  "FirefoxColor@mozilla.com".settings = {
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
}
