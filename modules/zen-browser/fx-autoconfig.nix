# fx-autoconfig loader wiring for the zen-browser home-manager module.
#
# Two halves have to line up.
#
# Program side: the loader files go into the *unwrapped* package, not the
# wrapFirefox output. wrapFirefox only copies files whose name matches
# `applicationName` ("zen-beta"), but Zen's actual binary inside the tarball is
# named "zen", so it is left as a symlink into the unwrapped store path. Firefox
# derives its GRE/app directory from the resolved /proc/self/exe, which means it
# reads defaults/pref and the autoconfig script from the unwrapped package and
# never sees the wrapper's mozilla.cfg or defaults/pref/autoconfig.js at all.
# Anything routed through extraPrefs/extraPrefsFiles is therefore silently
# inert. Installing upstream's program/ contents into the unwrapped package is
# both the documented method and the only one that actually takes effect here.
# It also stays correct if wrapFirefox is ever fixed to copy the binary, because
# defaults/pref/*.js load alphabetically and last wins: config-prefs.js sorts
# after the wrapper's autoconfig.js. (Caveat for that future: mozilla.cfg would
# then be shadowed, so extraPrefs would stop working. Nothing here uses it.)
#
# Profile side: chrome/utils/ and chrome/JS/ live in the mutable profile.
# chrome/utils is materialised as a real directory of symlinks (recursive =
# true) because utils/chrome.manifest registers namespaces with relative paths
# ("content userscripts ../JS/"). If chrome/utils were itself a symlink into the
# store, ".." would resolve into /nix/store and those namespaces would break.
{ inputs, variant }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mapAttrs'
    mapAttrsToList
    mkIf
    mkMerge
    mkOption
    nameValuePair
    types
    ;

  cfg = config.programs.zen-browser;

  fxAutoconfig = inputs.fx-autoconfig;

  # Only profiles that actually asked for scripts or styles get the loader.
  activeProfiles = lib.filterAttrs (
    _: profile: profile.userScripts != { } || profile.userStyles != { }
  ) cfg.profiles;

  profileDir = profile: "${cfg.profilesPath}/${profile.path}";

  # Instrumented stand-in for upstream's config.js. Upstream wraps the whole
  # loader chain in `catch(ex){}`, so any failure is invisible; this reports each
  # stage as a pref instead. pref() is the one API available in both autoconfig
  # sandbox modes, which is what makes it usable even if Cc/Ci are not. Values
  # land on the default branch: visible in about:config, absent from prefs.js,
  # and self-clearing once this is turned off. `typeof` on an undeclared name is
  # safe and does not throw.
  probeConfig = pkgs.writeText "fx-autoconfig-probe.js" ''
    // skip 1st line
    pref("uc.probe.reached", true);
    pref("uc.probe.typeofCc", typeof Cc);
    pref("uc.probe.typeofChromeUtils", typeof ChromeUtils);
    try {
      let cmanifest = Cc['@mozilla.org/file/directory_service;1']
        .getService(Ci.nsIProperties).get('UChrm', Ci.nsIFile);
      cmanifest.append('utils');
      cmanifest.append('chrome.manifest');
      pref("uc.probe.path", cmanifest.path);
      pref("uc.probe.exists", cmanifest.exists());
      if (cmanifest.exists()) {
        Components.manager.QueryInterface(Ci.nsIComponentRegistrar).autoRegister(cmanifest);
        pref("uc.probe.registered", true);
        ChromeUtils.importESModule('chrome://userchromejs/content/boot.sys.mjs');
        pref("uc.probe.imported", true);
      }
    } catch (ex) {
      pref("uc.probe.error", String(ex));
    }
  '';

  # Which script gets installed as the autoconfig file.
  loaderConfig = if cfg.userScriptsDebug then probeConfig else "${fxAutoconfig}/program/config.js";
in
{
  options.programs.zen-browser.userScriptsDebug =
    lib.mkEnableOption "the fx-autoconfig diagnostic probe"
    // {
      description = ''
        Swap upstream's silent config.js for an instrumented version that
        records how far the loader got in `uc.probe.*` prefs, readable from
        about:config. Diagnostic only -- leave off in normal use.
      '';
    };

  # Extend the profile submodule declared by home-manager's mkFirefoxModule.
  # Submodule types merge, so this composes with the upstream declaration.
  options.programs.zen-browser.profiles = mkOption {
    type = types.attrsOf (
      types.submodule {
        options.userScripts = mkOption {
          type = types.attrsOf (types.either types.lines types.path);
          default = { };
          example = lib.literalExpression ''{ "hello.uc.js" = ./scripts/hello.uc.js; }'';
          description = ''
            fx-autoconfig userscripts for this profile, keyed by file name. Names
            must end in .uc.js, .uc.mjs or .sys.mjs for the loader to pick them
            up. Setting this installs the fx-autoconfig loader into the profile's
            chrome/utils directory.

            A path value is linked as-is; a string value is written as file
            content. Note that an interpolated store path is a string and would
            therefore be treated as content -- use a path literal for files.
          '';
        };

        options.userStyles = mkOption {
          type = types.attrsOf (types.either types.lines types.path);
          default = { };
          example = lib.literalExpression ''{ "hello.css" = ./styles/hello.css; }'';
          description = ''
            fx-autoconfig userstyles for this profile, keyed by file name.
            Registered under the chrome.manifest "userstyles" namespace, so a
            file named here is reachable at chrome://userstyles/skin/<name>.
            Setting this installs the fx-autoconfig loader into the profile's
            chrome/utils directory, same as userScripts.

            A path value is linked as-is; a string value is written as file
            content. Note that an interpolated store path is a string and would
            therefore be treated as content -- use a path literal for files.
          '';
        };
      }
    );
  };

  config = mkIf (cfg.enable && activeProfiles != { }) {
    assertions = mapAttrsToList (profileName: profile: {
      assertion = !profile.sine.enable;
      message = ''
        programs.zen-browser.profiles.${profileName}: sine.enable installs its own
        config.js and defaults/pref/config-pref.js into the same package, which
        would fight with the fx-autoconfig loader. Use userScripts or sine, not both.
      '';
    }) activeProfiles;

    programs.zen-browser.unwrappedPackage =
      let
        zen = inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system};
      in
      (zen."${variant}-unwrapped".override {
        # Mirror what the flake's own hm-module does, so overriding the base
        # package here does not quietly drop these. These do take effect: the
        # unwrapped distribution/policies.json is the one Firefox actually reads,
        # for the same GRE-directory reason described at the top of this file.
        inherit (cfg) policies enablePrivateDesktopEntry;
      }).overrideAttrs
        (old: {
          # installPhase does `cp -r "$src"/*`, so the copied tree inherits
          # read-only store permissions, and postInstall runs before fixupPhase.
          # config.js is guarded by `if (cmanifest.exists())`, so it stays inert
          # until the profile half below lands.
          postInstall = (old.postInstall or "") + ''
            for libdir in "$out"/lib/zen-bin-*; do
              chmod -R u+w "$libdir"
              install -Dm444 ${loaderConfig} "$libdir/config.js"
              install -Dm444 ${fxAutoconfig}/program/defaults/pref/config-prefs.js \
                "$libdir/defaults/pref/config-prefs.js"
            done
          '';
        });

    home.file = mkMerge (
      mapAttrsToList (
        _: profile:
        {
          "${profileDir profile}/chrome/utils" = {
            source = "${fxAutoconfig}/profile/chrome/utils";
            recursive = true;
          };

          # utils/chrome.manifest registers four namespaces, and fs.sys.mjs
          # resolves three of them (userscripts -> ../JS, userchrome ->
          # ../resources, userstyles -> ../CSS) from a *static initialisation
          # block* that runs eagerly on module evaluation. A missing directory
          # makes that block throw, which fails the boot.sys.mjs import, which
          # config.js swallows in its catch -- a completely silent no-op. So
          # every directory named by the manifest has to exist, even if empty.
          "${profileDir profile}/chrome/resources/.keep".text = "";
        }
        // lib.optionalAttrs (profile.userStyles == { }) {
          "${profileDir profile}/chrome/CSS/.keep".text = "";
        }
        // mapAttrs' (
          fileName: script:
          nameValuePair "${profileDir profile}/chrome/JS/${fileName}" (
            if lib.isPath script then { source = script; } else { text = script; }
          )
        ) profile.userScripts
        // mapAttrs' (
          fileName: style:
          nameValuePair "${profileDir profile}/chrome/CSS/${fileName}" (
            if lib.isPath style then { source = style; } else { text = style; }
          )
        ) profile.userStyles
      ) activeProfiles
    );

    # Store files always carry a 1970 mtime, so Firefox's startup cache will not
    # invalidate itself when a script changes. Dropping it every switch costs one
    # slightly slower browser start and avoids debugging stale scripts. Gecko
    # keeps startupCache in the *local* profile dir, which under Zen's XDG layout
    # is ~/.cache/zen/<profile>; clear both spellings.
    home.activation.zenClearStartupCache = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.concatMapStrings (profile: ''
        run rm -rf ${lib.escapeShellArg "${profileDir profile}/startupCache"}
        run rm -rf ${lib.escapeShellArg "${config.xdg.cacheHome}/zen/${profile.path}/startupCache"}
      '') (lib.attrValues activeProfiles)
    );
  };
}
