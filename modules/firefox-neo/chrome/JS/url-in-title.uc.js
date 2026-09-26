// Window title "<page> — Mozilla Firefox" -> "<page> — <host>".
//
// Lets the compositor tell sites apart without talking to the browser:
// modules/keylayers matches layer `titles` against the window title, and
// Hyprland re-fires on title change. Only the OS window title changes --
// tab labels come from tab.label, not getWindowTitleForBrowser, so the tab
// strip and Sidebery still show the bare page title. Host only, never the
// full URL: the window title leaks into bars, share pickers, hyprctl.
// Pages without a host (about:, file:) keep the brand suffix.

(function () {
  if (!window.gBrowser || gBrowser.__urlInTitle) return;
  gBrowser.__urlInTitle = true;

  const SEP = " \u2014 "; // em dash, Firefox's own title separator
  const brand = SEP + Services.strings
    .createBundle("chrome://branding/locale/brand.properties")
    .GetStringFromName("brandFullName");

  const orig = gBrowser.getWindowTitleForBrowser.bind(gBrowser);
  gBrowser.getWindowTitleForBrowser = function (browser) {
    const title = orig(browser);
    let host = "";
    try {
      host = browser.currentURI.host;
    } catch (e) {} // nsSimpleURI (about:, data:) throws on .host
    return host && title.endsWith(brand) ? title.slice(0, -brand.length) + SEP + host : title;
  };

  // Firefox only retitles on tab switch / page-title change; a same-title
  // navigation to another host would otherwise keep the stale suffix.
  gBrowser.addProgressListener({
    QueryInterface: ChromeUtils.generateQI(["nsIWebProgressListener", "nsISupportsWeakReference"]),
    onLocationChange(progress) {
      if (progress.isTopLevel) gBrowser.updateTitlebar();
    },
  });
  gBrowser.updateTitlebar();
})();
