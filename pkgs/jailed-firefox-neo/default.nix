# firefox-neo in a throwaway HOME, for clean-room testing:
#
#   nix run /etc/nixos#jailed-firefox-neo
#
# Every launch gets a fresh $HOME seeded from a home-manager evaluation of
# modules/firefox-neo (profile, Sidebery + settings, userChrome, chrome/JS),
# and nothing survives exit. The host's real profile is never visible.
#
# The rest of the filesystem is bound as-is (fonts, /nix/store, the wayland
# socket) -- the point is to isolate *configuration*, not to sandbox the
# browser.
{
  lib,
  self,
  inputs,
  pkgs,
  writeShellApplication,
  bubblewrap,
  coreutils,
  firefox,
}:
let
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
          firefox.override { extraPrefsFiles = [ "${inputs.fx-autoconfig}/program/config.js" ]; }
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
writeShellApplication {
  name = "jailed-firefox-neo";
  runtimeInputs = [
    bubblewrap
    coreutils
  ];
  text = ''
    jail=$(mktemp -d "''${XDG_RUNTIME_DIR:-/tmp}/firefox-neo-jail.XXXXXX")
    trap 'rm -rf "$jail"' EXIT

    # Dereference: home-files is a tree of store symlinks, and Firefox has to
    # be able to write into its own profile.
    cp -rL --no-preserve=mode,ownership ${hm.config.home-files}/. "$jail"/

    # --no-remote: without it Firefox finds the host instance over dbus and
    # just opens a tab there, defeating the whole exercise.
    #
    # --tmpfs /home: bwrap cannot mkdir the bind target in the real /home
    # (unwritable), and the tmpfs hides every other user's home for free.
    bwrap \
      --dev-bind / / \
      --tmpfs /home \
      --bind "$jail" ${lib.escapeShellArg jailHome} \
      --setenv HOME ${lib.escapeShellArg jailHome} \
      --die-with-parent \
      ${lib.getExe ffCfg.finalPackage} --no-remote --profile ${lib.escapeShellArg profilePath} "$@"
  '';
  meta.mainProgram = "jailed-firefox-neo";
}
