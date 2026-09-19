# firefox-neo in a throwaway HOME, for clean-room testing:
#
#   nix run /etc/nixos#jailed-firefox-neo
#
# Every launch gets a fresh $HOME seeded from a home-manager evaluation of
# modules/firefox-neo (profile, Sidebery + settings, userChrome, chrome/JS),
# and nothing survives exit. The host's real profile is never visible.
#
# Built with jail.nix (same builder as pkgs/opencode-bubblewrap) rather than a
# hand-rolled bwrap line. The point is to isolate *configuration*, so the
# permission list is deliberately generous for a browser -- gui/gpu/network --
# and stops at the host's files.
{
  lib,
  self,
  inputs,
  pkgs,
  firefox,
}:
let
  jail = inputs.jail-nix.lib.extend { inherit pkgs; };

  jailHome = "/home/firefox-neo-jail";

  hm = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inherit self inputs; };
    modules = [
      self.homeModules.firefox-neo
      {
        home.username = "firefox-neo-jail";
        home.homeDirectory = jailHome;
        home.stateVersion = "24.05";

        # modules/firefox-neo points programs.firefox.package at the
        # callPackage'd self.packages.*.firefox-neo, whose `override` is
        # callPackage's (args: lib/firefox/inputs/extraPrefs) rather than
        # wrapFirefox's. home-manager calls `package.override { cfg = ...; }`,
        # which that lambda rejects. Rebuilding the same wrapper inline keeps
        # wrapFirefox's own override intact.
        programs.firefox.package = lib.mkForce (
          firefox.override {
            extraPrefsFiles = [ "${inputs.fx-autoconfig}/program/config.js" ];

            # modules/firefox-neo follows the system color scheme, which Firefox
            # learns from the desktop portal over dbus. The jail has no dbus, so
            # it falls back to light and the theme's light palette. Pin the
            # system hint dark; browser.theme.{toolbar,content}-theme are left at
            # their "follow system" default, so both chrome and content follow.
            extraPrefs = ''
              pref("ui.systemUsesDarkTheme", 1);
            '';
          }
        );
      }
    ];
  };
  ffCfg = hm.config.programs.firefox;

  # modules/firefox-neo uses a non-default configPath, so profiles.ini is
  # somewhere Firefox does not look. Naming the profile directory outright
  # sidesteps profiles.ini entirely.
  profilePath = "${jailHome}/${ffCfg.configPath}/${(lib.head (lib.attrValues ffCfg.profiles)).path}";
in
jail "jailed-firefox-neo" ffCfg.finalPackage (
  with jail.combinators;
  [
    network
    gui # wayland + pulse/pipewire + fonts + cursor + XDG_DATA_DIRS
    gpu

    # jail.nix's `base` already tmpfs-mounts the *host's* $HOME, but the
    # profile paths baked into the home-manager evaluation above are absolute
    # under jailHome, so the jail runs with HOME pointed there instead. It sits
    # on the root tmpfs bwrap sets up, hence the mkdir in wrap-entry.
    (set-env "HOME" jailHome)

    # browser-exec's bridge (loaded via modules/firefox-neo) binds a unix
    # socket under the real $XDG_RUNTIME_DIR, not under jailHome -- bound at
    # its real host path so opencode's jail (which binds the identical path,
    # see pkgs/opencode-bubblewrap) can reach whichever firefox-neo instance
    # happens to be running, this jailed one or the real profile.
    (add-runtime ''
      mkdir -p "$XDG_RUNTIME_DIR/browser-exec"
    '')
    (try-rw-bind (noescape "\"$XDG_RUNTIME_DIR/browser-exec\"") (noescape "\"$XDG_RUNTIME_DIR/browser-exec\""))

    # The userscript library ($HOME/.local/share/browser-exec) is read by
    # ScriptStore off *this jail's* $HOME, which is jailHome, not the real
    # host $HOME -- and jailHome is a fresh tmpfs wiped every launch, so
    # without this bind the library would silently look empty every time.
    # `add-runtime` still sees the real host $HOME (it runs before `set-env
    # "HOME"` takes effect inside the jail), so bind that real, persistent
    # dir at the jail-side jailHome path -- the same real directory
    # opencode's jail binds at its own $HOME, so a userscript written by one
    # jail is immediately visible to the other.
    (add-runtime ''
      mkdir -p "$HOME/.local/share/browser-exec/userscripts" "$HOME/.local/share/browser-exec/snippets"
    '')
    (rw-bind (noescape "\"$HOME/.local/share/browser-exec\"") "${jailHome}/.local/share/browser-exec")

    # Seed the throwaway home from the store, inside the jail -- nothing is
    # written on the host, so there is no temp dir to clean up.
    #
    # Dereference: home-files is a tree of store symlinks, and Firefox has to
    # be able to write into its own profile.
    (wrap-entry (entry: ''
      mkdir -p ${lib.escapeShellArg jailHome}
      cp -rL --no-preserve=mode,ownership ${hm.config.home-files}/. ${lib.escapeShellArg jailHome}/
      ${entry}
    ''))

    # --no-remote: without it Firefox finds the host instance over dbus and
    # just opens a tab there, defeating the whole exercise.
    (set-argv [
      "--no-remote"
      "--profile"
      profilePath
      (noescape "\"$@\"")
    ])
  ]
)
