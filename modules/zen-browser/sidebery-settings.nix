# Sidebery extension behaviour (context menu + settings), forked from
# modules/firefox/settings/extensionSettings.nix
# ("{3c078156-979c-498b-8990-85f7987dd929}".settings, minus sidebarCSS).
#
# CSS lives separately at ./styles/sidebery.css, injected through the
# fx-autoconfig userscript instead of extension storage -- see the top of
# extensionSettings.nix for why (the storage.js seed only takes effect once,
# on first extension install, then Firefox migrates it to IndexedDB and never
# rereads it).
#
# This block is still delivered via extensions.settings, so the same
# one-shot-seed caveat applies here: editing this file only changes what a
# *fresh* profile sees. To re-seed an existing profile, remove its
# browser-extension-data/{3c078156-979c-498b-8990-85f7987dd929}/ storage dir
# and the "ExtensionStorageIDB.migrated.{3c078156-...}" pref, then relaunch.
#
# Forked rather than shared with the Firefox module because AGENTS.md
# forbids cross-module relative-path references, and because Zen's tuning is
# expected to diverge from Firefox's over time.
{
  # Context menu configuration (matches Sidebery defaults from src/defaults/menu.ts)
  # Available tab options: undoRmTab, moveToNewWin, moveToWin, moveToPanel, moveToNewPanel,
  #   reopenInNewWin, reopenInWin, reopenInCtr, reopenInNewCtr, pin, reload, duplicate,
  #   bookmark, mute, discard, group, flatten, clearCookies, close, closeBranch,
  #   closeDescendants, closeTabsAbove, closeTabsBelow, closeOtherTabs, copyTabsUrls,
  #   copyTabsTitles, colorizeTab, editTabTitle, sortTabsByTitleAscending, etc.
  # Use "---" for separator
  contextMenu = {
    tabs = [
      {
        opts = [
          "undoRmTab"
          "mute"
          "reload"
          "bookmark"
        ];
      }
      "separator-1"
      {
        name = "%menu.tab.move_to_sub_menu_name";
        opts = [
          "moveToNewWin"
          "moveToWin"
          "separator-5"
          "moveToPanel"
          "moveToNewPanel"
        ];
      }
      {
        name = "%menu.tab.reopen_in_sub_menu_name";
        opts = [
          "reopenInNewWin"
          "reopenInWin"
          "separator-6"
          "reopenInCtr"
          "reopenInNewCtr"
        ];
      }
      {
        name = "%menu.tab.colorize_";
        opts = [ "colorizeTab" ];
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
      {
        opts = [
          "undoRmTab"
          "muteAllAudibleTabs"
          "reloadTabs"
          "discardTabs"
        ];
      }
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
}
