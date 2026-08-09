// Top-level layer-shell overlay. Fullscreen, exclusive keyboard focus while
// open -- this is meant to be driven entirely by a remote's D-pad, never a
// mouse, so there is no window chrome and no pointer handling anywhere here.
//
// Kept on graphical-session.target (see modules/tv-files.nix), not
// tv-active.target: destroying this window during idle teardown would make
// Hyprland's focus path fire a spurious resume, the same bug the tv-away
// module works around for Spotify. The window just stays mapped and hidden.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services"
import "."

PanelWindow {
  id: root
  visible: State.open

  WlrLayershell.namespace: "quickshell:tv-files"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  color: "transparent"

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.bg

    RowLayout {
      anchors.fill: parent
      anchors.margins: 40
      spacing: 30

      Sidebar {
        id: sidebar
        Layout.preferredWidth: 340
        Layout.fillHeight: true
        onActivated: (path) => {
          State.currentPath = path;
          fileGrid.focusGrid();
        }
        onRequestGrid: fileGrid.focusGrid()
      }

      FileGrid {
        id: fileGrid
        Layout.fillWidth: true
        Layout.fillHeight: true
        onRequestSidebar: sidebar.focusList()
      }
    }
  }

  onVisibleChanged: if (visible) fileGrid.focusGrid()

  IpcHandler {
    target: "browser"

    function toggle(): void {
      if (State.open) {
        State.open = false;
      } else {
        State.reset();
        State.open = true;
      }
    }
    function open(): void {
      State.reset();
      State.open = true;
    }
    function close(): void {
      State.open = false;
    }
  }
}
