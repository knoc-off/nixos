// The main pane: FolderListModel of State.currentPath rendered as a grid,
// arrow-key navigable (GridView handles Up/Down/Right natively; Left is
// intercepted at column 0 to hand focus back to the sidebar). Return
// descends into directories or opens files via xdg-open, which resolves
// through the mimeapps.list already configured in modules/users/tv.nix --
// no new open-handler wiring needed here.
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell.Io
import "../services"

Item {
  id: root
  signal requestSidebar()

  readonly property int cellW: 220
  readonly property int cellH: 190
  readonly property int columns: Math.max(1, Math.floor(width / cellW))

  FolderListModel {
    id: flm
    folder: State.currentPath
    showDirsFirst: true
    showDotAndDotDot: false
    sortField: FolderListModel.Name
  }

  Process {
    id: openProc
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: 16

    Text {
      Layout.fillWidth: true
      text: decodeURIComponent(String(State.currentPath).replace("file://", ""))
      color: Theme.fgMuted
      font.pixelSize: 22
      elide: Text.ElideMiddle
    }

    GridView {
      id: grid
      Layout.fillWidth: true
      Layout.fillHeight: true
      cellWidth: root.cellW
      cellHeight: root.cellH
      model: flm
      focus: true
      clip: true
      highlightFollowsCurrentItem: true

      delegate: Tile {
        width: grid.cellWidth - 12
        height: grid.cellHeight - 12
        fileName: model.fileName
        isDir: model.fileIsDir
        current: GridView.isCurrentItem
      }

      Keys.onLeftPressed: (event) => {
        if (grid.currentIndex % root.columns === 0) {
          event.accepted = true;
          root.requestSidebar();
        }
      }

      Keys.onReturnPressed: activate()
      Keys.onEnterPressed: activate()
      Keys.onEscapePressed: State.open = false
      // Backspace has no dedicated Keys.onXPressed convenience signal in Qt,
      // unlike Return/Enter/Escape/arrows -- has to go through onPressed.
      Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Backspace) {
          up();
          event.accepted = true;
        }
      }

      function activate() {
        if (currentIndex < 0 || currentIndex >= flm.count) return;
        if (flm.get(currentIndex, "fileIsDir")) {
          State.currentPath = flm.get(currentIndex, "fileUrl").toString();
          currentIndex = 0;
        } else {
          openProc.command = [ "xdg-open", flm.get(currentIndex, "filePath") ];
          openProc.running = true;
        }
      }

      function up() {
        var parent = flm.parentFolder;
        if (parent && parent.toString() !== "") {
          State.currentPath = parent.toString();
          currentIndex = 0;
        }
      }
    }
  }

  function focusGrid() {
    grid.forceActiveFocus();
  }
}
