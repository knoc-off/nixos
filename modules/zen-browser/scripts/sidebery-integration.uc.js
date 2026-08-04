// ==UserScript==
// @name           Sidebery integration for Zen
// @description    Reparents Sidebery's sidebar into Zen's tab strip, replacing Zen's native tabs.
// ==/UserScript==
//
// Vendored from https://github.com/Erudition/zen-sidebery-mod
//   file:    zen-sidebery-integration.mjs
//   commit:  4026af6660bcbb091cf7f1087702d9e240b43aff
//   date:    2025-05-08
//   license: AGPL-3.0
//
// Upstream is unmaintained (no commits since the date above) and its documented
// install method is `fetch(...).then(eval)`, i.e. unpinned remote code executed
// at every startup. Vendored instead so it is pinned, reviewable in git, and
// patchable. Local changes vs upstream are marked "LOCAL:" below.
//
// This script pokes at Zen internals (#TabsToolbar-customization-target,
// #zen-sidebar-top-buttons, --zen-* CSS variables). Expect it to need attention
// after Zen upgrades.

const { ExtensionUtils } = ChromeUtils.importESModule(
    "resource://gre/modules/ExtensionUtils.sys.mjs"
);

var { promiseEvent } = ExtensionUtils;

let sidebery_policy;
let sidebery_url;
let sidebery_extension;


// Fetch first extension matching the name if any
sidebery_policy = WebExtensionPolicy.getActiveExtensions().filter((ext) => ext.name === "Sidebery")[0];
if (sidebery_policy) {
    sidebery_extension = sidebery_policy.extension;
    sidebery_url = sidebery_extension.manifest.sidebar_action.default_panel;

    // LOCAL: upstream rewrites Sidebery's baseCSP here to permit 'unsafe-eval',
    // 'unsafe-inline' and script-src from https://*, which permanently weakens
    // the extension's own sandbox for the whole session. Left disabled to see
    // whether Sidebery works without it. If the panel renders blank or its
    // console shows CSP violations, re-enable and accept the tradeoff.
    // sidebery_policy.baseCSP = "script-src 'self' https://* http://localhost:* http://127.0.0.1:* moz-extension: chrome: blob: filesystem: 'unsafe-eval' 'wasm-unsafe-eval' 'unsafe-inline' chrome:;"

    console.log("1. Found Sidebery extension.");
}



async function setupSideberyPanel(win) {
    // LOCAL: guard against double-injection leaving two <browser> elements.
    if (win.sidebery_browser) {
        console.log("Sidebery already set up in this window; skipping.");
        return;
    }
    // add a separate <browser> element outside of sidebar
    // https://udn.realityripple.com/docs/Archive/Mozilla/XUL/browser
    win.sidebery_browser = win.document.createXULElement("browser");
    win.sidebery_browser.setAttribute("id", "sidebery");
    win.sidebery_browser.setAttribute("type", "content"); // try content-primary for direct access?
    win.sidebery_browser.setAttribute("flex", "1");
    win.sidebery_browser.setAttribute("disableglobalhistory", "true");
    win.sidebery_browser.setAttribute("disablehistory", "true");
    win.sidebery_browser.setAttribute("disablesecurity", "true");
    win.sidebery_browser.setAttribute("messagemanagergroup", "webext-browsers");
    // LOCAL: upstream left this commented out ("needed?"). It is required.
    // ExtensionParent.sys.mjs's GlobalManager._onExtensionBrowser reads this
    // attribute off the browser element when "extension-browser-inserted"
    // fires (below, in afterSideberyLoads) and only registers the frame's
    // viewType if it is set; "sidebar" is the value that maps to a valid
    // contextType ("SIDE_PANEL"). Without it, every IPC-backed WebExtension
    // API (tabs.*, storage.*, windows.*) hangs forever on this frame -- only
    // synchronous calls like runtime.getManifest() work -- which is why the
    // panel rendered its shell but never any tabs: Sidebery's init call to
    // browser.tabs.query() never resolved.
    win.sidebery_browser.setAttribute("webextension-view-type", "sidebar");
    win.sidebery_browser.setAttribute("context", "tabContextMenu"); // replace with tab are context menu?
    win.sidebery_browser.setAttribute("tooltip", "tabbrowser-tab-tooltip"); //replace with tab area tooltip?
    win.sidebery_browser.setAttribute("autocompletepopup", "PopupAutoComplete");
    win.sidebery_browser.setAttribute("transparent", "true");
    // Ensure that the browser is going to run in the same bc group as the other
    // extension pages from the same addon.
    win.sidebery_browser.setAttribute("initialBrowsingContextGroupId", sidebery_policy.browsingContextGroupId);

    // make it remote - simply does not work otherwise
    win.sidebery_browser.setAttribute("remote", "true");
    win.sidebery_browser.setAttribute("remoteType", "extension"); // sidebery needs this to access windows
    //win.sidebery_browser.setAttribute("maychangeremoteness", "true"); // it won't

    // load dynamically instead
    //win.sidebery_browser.setAttribute("src", sidebery_url); //moz-extension://975176be-3729-46a4-84fc-204e044f42d3/sidebar/sidebar.html


    //only seems to work as a promiseEvent, not a normal event handler
    // LOCAL: declared -- upstream leaked these two into global scope.
    let awaitFrameLoader = promiseEvent(win.sidebery_browser, "XULFrameLoaderCreated");

    // time to insert, <browser> will be constructed
    let oldTabsContainer = win.document.querySelector("#TabsToolbar-customization-target");
    oldTabsContainer.insertAdjacentElement('afterend', win.sidebery_browser);
    console.log("2. Sidebery's browser frame element has been set up.");
    await awaitFrameLoader;
    //oldTabsContainer.style.display = "none";
    loadSideberyPanel(win);
}

function loadSideberyPanel(win) {
    console.log("3. Loading Sidebery into frame...");



    // System Principal should let Sidebery do anything chrome can do, so it's legit native
    let triggeringPrincipal = Services.scriptSecurityManager.getSystemPrincipal();
    win.sidebery_browser.loadURI(Services.io.newURI(sidebery_url), { triggeringPrincipal });
    // win.sidebery_browser.addEventListener("load", afterSideberyLoads, true);

    const css = `
    #zen-sidebar-splitter { 
        background-color: var(--zen-colors-border); /* put it back from transparent (normally 0 opacity anyway) */
        margin-left: calc(0px - var(--zen-toolbox-padding)); /* allow tabs to go under it */
    }
    #zen-sidebar-splitter:hover { opacity: 0.5 }
    *[draggable="true"], .browser-toolbar {
        -moz-window-dragging: no-drag;
    }

    #navigator-toolbox:not([zen-sidebar-expanded="true"]) {
        & #titlebar {
            display: revert; /* was grid for compact mode */
        }
    }

    :root {
    --zen-workspace-indicator-height: 40px; /* Enable side by side comparison of tabs */
    }

    /* Future feature: overflow when hovering over collapsed toolbar
    #navigator-toolbox:not([zen-sidebar-expanded="true"]):not([zen-right-side="true"]):hover {

        max-width: 250px !important;
        z-index: var(--browser-area-z-index-toolbox-while-animating);
        margin-right: calc(0px - var(--tabbar-overlap));
        --tabbar-overlap: calc(250px - var(--zen-toolbox-max-width));
        padding-right: var(--tabbar-overlap);
        width: 250px !important;

        & #sidebery {
            margin-right: calc(0px - var(--tabbar-overlap));
        }
    }
    */
    `;

    var style = win.document.createElement('style');

    if (style.styleSheet) {
        style.styleSheet.cssText = css;
    } else {
        // LOCAL: was bare `document`, which is the wrong document once more
        // than one browser window exists.
        style.appendChild(win.document.createTextNode(css));
    }

    win.document.getElementsByTagName('head')[0].appendChild(style);
    console.log("4. Ready for Sidebery to load.");
    afterSideberyLoads(win);
}


function getZenCSSVariables() {
    // TODO see if this is needed for dynamic updates
    const rootStyle = getComputedStyle(window.document.getElementById("tabbrowser-tabs"));
    let css = '';
    for (const property of rootStyle) {
        if (property.startsWith("--")) {
            css += `${property}: ${rootStyle.getPropertyValue(property).trim()};\n`;
        }
    }
    return `:root {\n${css}\n}`;
}


const fixNoGrabbingCursorOnDrag = // attempt to fix bug #3
    `
    #root.root[data-drag="true"], #root.root[data-drag="true"] .AnimatedTabList *, #root.root[data-drag="true"] .Tab, #root.root[data-drag="true"] .drag_image, #root.root[data-drag="true"] .pointer {
        cursor: grabbing !important;
    }
`

const transparentByDefault = //fixes bug #2
    `
    :root {background-color: transparent;}
    #root.root {
        --frame-bg: transparent;
        --toolbar-bg: transparent;
    }
`

const fixInheritBadBrowserStyles = // some zen/ff styles make things worse, put it back
    `
    :root {
        &:not([chromehidden~="toolbar"]) {
            min-width: revert !important; /* was 450px in chrome://browser/skin/browser-shared.css -- too wide */
            min-height: revert; /* was 120px in chrome://browser/skin/browser-shared.css  -- let sidebery decide */
        }
    }

    @media not (forced-colors) {
        .close-icon:hover {
            background-color: revert;
        }
    }

    .close-icon {
        border-radius: revert;
        padding: revert;
        width: revert;
        height: revert;
        outline: revert;
    }
`


const handleCompactMode = //collapsed toolbar goes down to 60px (see sidebery-collapse.css) - hide nesting
    `
@media screen and (max-width: 90px) {
    .Tab[data-lvl] {
        padding-left: 0;
    }

    .NavigationBar .static-btns {
        flex-direction: column;
    }

    /* Sidebery lays the panel buttons out left-aligned, which is off-centre in
       a 60px rail. Centre them instead. Sidebery's own width-based CSS already
       hides the text label (.name-box) at this width, so only the icon
       remains -- this is purely about where that icon sits. */
    .NavigationBar .main-items,
    .NavigationBar .static-btns {
        justify-content: center;
    }

    .NavigationBar .nav-item {
        margin-left: auto;
        margin-right: auto;
    }

    /* The search bar is just a magnifier glyph at this width -- 32px of the
       rail spent on something unusable until it is expanded. */
    #search_bar {
        display: none;
    }

    .BottomBar {
        display:none;
    }

}

`


// const fixWidthRoundingUp = // Zen's sidebar tends to have non-integer width (like 356.667), but the sidebery frame's width is a rounded version, causing it to be cut off by a fraction of a pixel
//     `
// html {
//     border: 4px solid red;
// }
// `


// Sidebery reads --tabs-margin back out of computed style with a naive
// "first number in the string" parser, and derives the drag/drop row pitch as
// --tabs-height + --tabs-margin (chunk-NZV6P7I6.js: `Ig()` walks the tab list
// accumulating `c += n + i`). CSS resolves calc() properly, but that parser
// does not: `calc(2px * 2)` renders as 4px yet parses as 2. The drop-indicator
// rows then advance 2px less than the tabs actually do, so the insertion
// marker drifts further out of place the further down the list you drag.
// Emitting a literal keeps both readers in agreement.
//
// --tabs-height is deliberately left as var(--tab-min-height): a bare var()
// resolves to a plain "28px" that the same parser handles correctly. It is
// also NOT safe to bake in here -- getZenCSSVariables() snapshots Zen's
// variables once at startup, and --tab-min-height drifts afterwards (measured
// 28px in the snapshot vs 36px live mid-session), so resolving it eagerly
// would silently change tab height rather than just fixing the pitch.
function zenNumericVar(prop, fallback) {
    const probe = window.document.getElementById("tabbrowser-tabs");
    if (!probe) return fallback;
    const raw = getComputedStyle(probe).getPropertyValue(prop).trim();
    const parsed = parseFloat(raw);
    return Number.isFinite(parsed) ? parsed : fallback;
}

const tabsMarginPx = zenNumericVar("--tab-block-margin", 2) * 2;

const zenStylesByDefault = // fixes bug #4
    `
    #root {
    --general-border-radius: var(--zen-border-radius);
	--s-frame-bg: var(--zen-themed-toolbar-bg-transparent);
	--s-frame-fg: inherit;
	--s-toolbar-bg: var(--zen-themed-toolbar-bg);
	--s-toolbar-fg: inherit;
	--s-act-el-bg: rgba(106,106,120,0.7);
	--s-act-el-fg: rgb(255,255,255);
	--s-popup-bg: var(--arrowpanel-background);
	--s-popup-fg: var(--arrowpanel-color);
	--s-popup-border: var(--zen-colors-border);
    --nav-btn-fg: var(--toolbarbutton-icon-fill);

    --nav-btn-width: calc(2 * var(--toolbarbutton-inner-padding) + 16px);
    --nav-btn-height: calc(2 * var(--toolbarbutton-inner-padding) + 16px);
    --nav-btn-border-radius: var(--toolbarbutton-border-radius);
    --tabs-activated-bg: var(--tab-selected-bgcolor);
    --tabs-activated-shadow: var(--tab-selected-shadow);
    --tabs-activated-fg: var(--tab-selected-textcolor);
    --tabs-border-radius: var(--border-radius-medium);
    --tab-hover-background-color: var(--active-el-overlay-hover-bg);
    --tabs-font: message-box;
    --tabs-height: var(--tab-min-height);
    --tabs-margin: ${tabsMarginPx}px;


    }
    .SubPanel {
    	--s-frame-bg: var(--zen-themed-toolbar-bg-transparent);
	    --s-frame-fg: inherit;
    }
    body {
        color: var(--toolbox-textcolor);
        &:-moz-window-inactive {
            color: var(--toolbox-textcolor-inactive);
        }
    }
    .fav-icon {
        border-radius: 4px;
    }

    div.BottomBar, div.bottom-bar-space {
        display: none; /* Hide for now */
    }
`


// LOCAL: declared -- upstream leaked this into global scope.
const allStyleMods = [getZenCSSVariables(), fixNoGrabbingCursorOnDrag, transparentByDefault, fixInheritBadBrowserStyles, zenStylesByDefault, handleCompactMode]

function afterSideberyLoads(win) {
    console.log("5. Sidebery has loaded! Inserting scripts and styles.");
    win.sidebery_browser.messageManager.loadFrameScript(
        "chrome://extensions/content/ext-browser-content.js",
        false,
        true
    );
    let { ExtensionParent } = ChromeUtils.importESModule(
        "resource://gre/modules/ExtensionParent.sys.mjs"
    );

    ExtensionParent.apiManager.emit(
        "extension-browser-inserted",
        win.sidebery_browser
    );

    const zenStylesheets = [...win.document.styleSheets].map((styleSheet) => { return styleSheet.href; });
    const allStyleModsAsDataURLs = allStyleMods.map((css) => `data:text/css,${encodeURIComponent(css)}`);

    // LOCAL: custom Sidebery styling, delivered through fx-autoconfig's
    // "userstyles" chrome.manifest namespace (chrome/CSS -> chrome://userstyles/skin/).
    // Kept as its own stylesheet URL rather than folded into allStyleMods so it
    // stays a plain, syntax-highlighted .css file. Appended last so it wins
    // ties against the six mods above.
    let stylesheets = [...zenStylesheets, "chrome://browser/content/extension.css", ...allStyleModsAsDataURLs, "chrome://userstyles/skin/sidebery.css"].filter(sheet => sheet); //discard nulls
    console.log(stylesheets);
    win.sidebery_browser.messageManager.sendAsyncMessage("Extension:InitBrowser", { stylesheets });


    //keep inner browser zoom in sync with outer
    // LOCAL: upstream referenced a bare `browser` here, which is not defined in
    // this scope -- both handlers threw on every zoom event. Bound to the
    // sidebery frame instead.
    const zoomBy = (delta) => {
        const { ZoomManager } = win.sidebery_browser.ownerGlobal;
        let zoom = win.sidebery_browser.fullZoom + delta;
        zoom = Math.min(Math.max(zoom, ZoomManager.MIN), ZoomManager.MAX);
        win.sidebery_browser.fullZoom = zoom;
    };

    win.sidebery_browser.addEventListener("DoZoomEnlargeBy10", () => zoomBy(0.1), true);
    win.sidebery_browser.addEventListener("DoZoomReduceBy10", () => zoomBy(-0.1), true);

    // ignore window close command
    win.sidebery_browser.addEventListener("DOMWindowClose", event => { event.stopPropagation(); });
    // LOCAL: upstream popped a modal alert() here on every window creation.
    console.log("6. Sidebery mod complete. Hiding original Zen Tabs...");
    // LOCAL: declared -- upstream leaked this into global scope.
    let oldTabsContainer = win.document.querySelector("#TabsToolbar-customization-target");
    // Zen's bars are right next to Sidebery's, looks ugly with both - hide Zen's for now, buttons can be moved elsewhere
    //win.document.getElementById("zen-sidebar-bottom-buttons").style.display = "none";
    win.document.getElementById("zen-sidebar-top-buttons").style.display = "none";
    oldTabsContainer.style.display = "none";
}

function sideberyMissing(win) {
    let spotlight = {
        "weight": 100,
        "id": "get_sidebery_promo",
        // "groups": [
        //   "panel-test-provider"
        // ],
        "template": "spotlight",
        "content": {
            "template": "multistage",
            "backdrop": "transparent",
            "screens": [
                {
                    "id": "UPGRADE_PIN_FIREFOX",
                    "content": {
                        "logo": {
                            "imageURL": "https://raw.githubusercontent.com/mbnuqw/sidebery/v5/docs/assets/readme-logo.svg",
                            "height": "73px"
                        },
                        "has_noodles": true,
                        "title": {
                            "fontSize": "36px",
                            "raw": "Ready for Sidebery"
                        },
                        "title_style": "fancy shine",
                        "background": "url('chrome://activity-stream/content/data/content/assets/confetti.svg') top / 100% no-repeat var(--in-content-page-background)",
                        "subtitle": {
                            "raw": "You need to have the Sidebery addon installed and activated for Zen integration."
                        },
                        "primary_button": {
                            "label": {
                                "raw": "Get the addon"
                            },
                            "action": {
                                "data": {
                                    "args": "https://addons.mozilla.org/en-US/firefox/addon/sidebery/",
                                    // "where": "tabshifted"
                                },
                                "type": "OPEN_URL",
                                "navigate": true
                            }
                        },
                        "secondary_button": {
                            "label": {
                                "string_id": "onboarding-not-now-button-label"
                            },
                            "action": {
                                "navigate": true
                            }
                        }
                    }
                }
            ]
        },
        "trigger": {
            "id": "defaultBrowserCheck"
        },
        "targeting": "false",
        // "provider": "panel_local_testing"
    };
    ASRouter.routeCFRMessage(spotlight, win, spotlight.trigger, true);
}

function setup(win = window) {
    if (sidebery_policy) {
        setupSideberyPanel(win);
    } else {
        // LOCAL: upstream called this with no argument, but the signature takes
        // `win` -- it threw on the "Sidebery not installed" path.
        sideberyMissing(win);
    }
}

// apply to new windows
// windowListener = {
//     onOpenWindow(xulWindow) {
//         const win = xulWindow.docShell.domWindow;
//         win.addEventListener(
//             "load",
//             function () {
//                 if (
//                     win.document.documentElement.getAttribute("id") != "main-window"
//                 ) {
//                     return;
//                 }
//                 // Found the window
//                 setupSideberyPanel(win);
//             },
//             { once: false }
//         );
//     },
//     onCloseWindow() { },
// };
// Services.wm.addListener(windowListener);


// LOCAL: upstream registered a Services.wm window listener here to catch new
// windows, because it was designed to be eval'd once from the console. Under
// fx-autoconfig this whole script is already injected into every browser window
// as it is created, so the listener was both redundant and harmful: each window
// registered another listener, and the next window would then be set up twice
// (once by injection, once per accumulated listener). Removed.


// TODO
// function installScriptToEachNewWindow() {
//     // https://firefox-source-docs.mozilla.org/browser/CategoryManagerIndirection.html
// Services.catMan.addCategoryEntry(
//     "browser-window-delayed-startup",
//     "https://raw.githubusercontent.com/Erudition/zen-sidebery-mod/refs/heads/main/zen-sidebery-integration.mjs",
//     "TabUnloader.init",
//     true,
//     true
// )
// }


setup();