{ pkgs, ... }:
# xdg-desktop-portal RemoteDesktop backend for Hyprland.
#
# KDE Connect's mousepad plugin drives remote input through
# org.freedesktop.portal.RemoteDesktop (ConnectToEIS -> libei sender, with the
# legacy Notify* calls as fallback). Nothing implements that interface for
# Hyprland: xdg-desktop-portal-hyprland ships only Screenshot/ScreenCast/
# GlobalShortcuts, and Hyprland's own EIS server hangs off InputCapture and
# explicitly disconnects sender clients. xdg-desktop-portal-kde implements it
# against KWin, so routing to it does nothing here.
#
# This bridge fills that one interface and injects via
# zwlr_virtual_pointer_manager_v1 + zwp_virtual_keyboard_manager_v1, both of
# which Hyprland does speak.
#
# NOTE: upstream self-describes as "99% vibe coded". It is a D-Bus service whose
# job is injecting synthetic input into the session. Local-session use only.
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "hypr-kdeconnect-portal";
  version = "0-unstable-2026-07-26";

  src = pkgs.fetchFromGitHub {
    owner = "gfhdhytghd";
    repo = "hypr-kdeconnect-fix";
    rev = "e86a0fb17826cb8ea987665ded7428534e4a1a9d";
    hash = "sha256-VcXxVtlnkPjO6l0ky/n+0qa87Uc3c8hRM0twfgl+AiM=";
  };

  nativeBuildInputs = with pkgs; [
    cmake
    pkg-config
    wayland-scanner
    qt6.wrapQtAppsHook
  ];

  buildInputs = with pkgs; [
    qt6.qtbase
    wayland
    libxkbcommon
    libei # provides libeis-1.0
  ];

  # Upstream bakes @CMAKE_INSTALL_FULL_BINDIR@ into the .portal, D-Bus service
  # and systemd unit via configure_file, so the store paths come out correct
  # with no substituteInPlace needed.
  cmakeFlags = [
    (pkgs.lib.cmakeBool "BUILD_TESTING" true)
  ];

  doCheck = true;

  meta = {
    description = "RemoteDesktop portal backend bridging KDE Connect input to wlroots virtual-input protocols";
    homepage = "https://github.com/gfhdhytghd/hypr-kdeconnect-fix";
    license = pkgs.lib.licenses.mit;
    mainProgram = "hypr-kdeconnect-portal";
    platforms = pkgs.lib.platforms.linux;
  };
})
