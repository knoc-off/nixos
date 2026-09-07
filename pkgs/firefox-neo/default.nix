# firefox-neo: Firefox with the fx-autoconfig loader wired in.
#
# Runnable standalone for iteration:
#
#   nix run /etc/nixos#firefox-neo
#
# That gives a browser whose *program* half can load userscripts. The profile
# half (chrome/utils, chrome/JS, chrome/CSS) is what actually supplies scripts,
# and lives in the mutable profile -- see modules/firefox-neo, which materialises
# it and ships the scripts in modules/firefox-neo/chrome/.
#
# Why extraPrefsFiles is enough here, when the Zen equivalent needed a whole
# unwrapped-package override: wrapFirefox only copies files whose name matches
# `applicationName` and symlinks the rest, and Firefox derives its GRE/app
# directory from the resolved binary path. Zen's binary is named "zen" while its
# applicationName is "zen-beta", so the binary stayed a symlink into the
# unwrapped package and Firefox never saw the wrapper's mozilla.cfg. Plain
# Firefox's binary is named "firefox", matching applicationName, so it is copied
# into the wrapper output and the wrapper's own mozilla.cfg is the one that
# loads. The nixpkgs wrapper writes defaults/pref/autoconfig.js itself with
# general.config.filename=mozilla.cfg, and appends each extraPrefsFiles entry
# into mozilla.cfg -- which is precisely the autoconfig hook fx-autoconfig wants.
{
  lib,
  firefox,
  inputs,
  # Appended to mozilla.cfg after the loader. Exposed so a caller can build a
  # variant with extra autoconfig prefs without editing this file.
  extraPrefs ? "",
}:
let
  fxAutoconfig = inputs.fx-autoconfig;
in
# Plain .override, deliberately not wrapped in overrideAttrs. home-manager's
# firefox module re-overrides whatever package it is given (it passes its own
# cfg/extraPolicies/pkcs11Modules through package.override), and overrideAttrs
# replaces the derivation's `override` with one that only knows the wrapper's
# original arguments -- so an overrideAttrs'd package fails there with
# "called with unexpected argument 'cfg'". Keeping the wrapper's own override
# intact means both `nix run .#firefox-neo` and the home-manager module work
# from this one derivation.
firefox.override {
  extraPrefsFiles = [ "${fxAutoconfig}/program/config.js" ];
  inherit extraPrefs;
}
