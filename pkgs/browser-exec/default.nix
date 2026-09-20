{
  lib,
  stdenv,
}:

# browser-exec: a Firefox bridge (unix-socket chrome/page eval, fx-autoconfig
# userscript loader) plus the OpenCode plugin that talks to it. Same shape as
# pkgs/script-exec: no daemon, no binary. The chrome/JS half is installed into
# firefox-neo's profile by modules/firefox-neo; the plugin half runs inside
# the opencode jail. See bridge.sys.mjs and opencode-plugin.js for protocol and
# tool documentation respectively.
stdenv.mkDerivation {
  pname = "browser-exec";
  version = "0.1.0";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/browser-exec/plugin
    cp ${./opencode-plugin.js} $out/lib/browser-exec/plugin/index.js

    # Materialised into firefox-neo's profile chrome/JS by
    # modules/firefox-neo/default.nix. match.mjs is imported by both the
    # actor (as chrome://userscripts/content/match.mjs) and test.mjs under
    # node:test, so it has to stay free of Gecko/node-specific APIs -- see
    # its own header comment.
    mkdir -p $out/lib/browser-exec/chrome/JS/actor
    # bridge.sys.mjs, not bridge.uc.js: a *.sys.mjs under chrome/JS is imported
    # once per process into the shared module global, where it outlives every
    # window. As a per-window *.uc.js the socket bind either rebound on each
    # new window or died with the first window's compartment -- see the file's
    # own header for both failure modes.
    cp ${./bridge.sys.mjs} $out/lib/browser-exec/chrome/JS/bridge.sys.mjs
    cp ${./loader.sys.mjs} $out/lib/browser-exec/chrome/JS/loader.sys.mjs
    cp ${./match.mjs} $out/lib/browser-exec/chrome/JS/match.mjs
    cp ${./actor/store.sys.mjs} $out/lib/browser-exec/chrome/JS/actor/store.sys.mjs
    cp ${./actor/BrowserExecUserscriptsParent.sys.mjs} $out/lib/browser-exec/chrome/JS/actor/BrowserExecUserscriptsParent.sys.mjs
    cp ${./actor/BrowserExecUserscriptsChild.sys.mjs} $out/lib/browser-exec/chrome/JS/actor/BrowserExecUserscriptsChild.sys.mjs

    runHook postInstall
  '';

  meta = {
    description = "Firefox chrome/page eval bridge + userscript loader, and the OpenCode tool that drives it";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
