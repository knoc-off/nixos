// Places list: static shortcuts from Theme.places (set per-host in
// modules/users/tv.nix), plus whatever udisks2/devmon currently has mounted
// under /run/media/tv. A plain Repeater in a Column rather than a ListView --
// this list is always short, so virtualization buys nothing and a Repeater
// keeps index math trivial.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Qt.labs.folderlistmodel
import "../services"

Item {
  id: root
  signal activated(string path)
  signal requestGrid()

  property int currentIndex: 0
  readonly property int placeCount: Theme.places.length
  readonly property int totalCount: placeCount + removable.count

  FolderListModel {
    id: removable
    folder: "file:///run/media/tv"
    showDirs: true
    showFiles: false
    showDotAndDotDot: false
  }

  function nameAt(i) {
    return i < placeCount ? Theme.places[i].name : removable.get(i - placeCount, "fileName");
  }
  function iconAt(i) {
    return i < placeCount ? Theme.places[i].icon : "drive-removable-media";
  }
  function pathAt(i) {
    return i < placeCount ? Theme.places[i].path : removable.get(i - placeCount, "fileUrl").toString();
  }

  Rectangle {
    anchors.fill: parent
    radius: 16
    color: Theme.bgAlt

    Column {
      anchors.fill: parent
      anchors.margins: 16
      spacing: 8

      Repeater {
        model: root.totalCount

        delegate: Rectangle {
          width: parent.width
          height: 56
          radius: 10
          color: index === root.currentIndex ? Theme.accent : "transparent"

          Row {
            anchors.fill: parent
            anchors.leftMargin: 12
            spacing: 12

            IconImage {
              anchors.verticalCenter: parent.verticalCenter
              implicitSize: 28
              source: Quickshell.iconPath(root.iconAt(index), "folder")
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.nameAt(index)
              color: index === root.currentIndex ? Theme.bg : Theme.fg
              font.pixelSize: 18
            }
          }
        }
      }
    }
  }

  Keys.onDownPressed: currentIndex = Math.min(currentIndex + 1, totalCount - 1)
  Keys.onUpPressed: currentIndex = Math.max(currentIndex - 1, 0)
  Keys.onRightPressed: requestGrid()
  Keys.onReturnPressed: activated(pathAt(currentIndex))
  Keys.onEnterPressed: activated(pathAt(currentIndex))
  Keys.onEscapePressed: State.open = false

  function focusList() {
    forceActiveFocus();
  }
}
