// A single grid entry: icon (looked up from the system theme, so it matches
// whatever icons Dolphin/etc. use) plus a two-line name label.
import QtQuick
import Quickshell
import Quickshell.Widgets
import "../services"

Rectangle {
  id: root
  property string fileName: ""
  property bool isDir: false
  property bool current: false

  radius: 12
  color: current ? Theme.accent : Theme.surface
  border.width: current ? 0 : 1
  border.color: Theme.border

  readonly property string iconName: {
    if (isDir) return "folder";
    var ext = fileName.includes(".") ? fileName.split(".").pop().toLowerCase() : "";
    if ([ "mp4", "mkv", "webm", "avi", "mov", "mpeg", "mpg" ].includes(ext)) return "video-x-generic";
    if ([ "mp3", "ogg", "wav", "flac", "aac", "wma", "m4a" ].includes(ext)) return "audio-x-generic";
    if ([ "jpg", "jpeg", "png", "gif", "bmp", "svg", "tiff", "webp" ].includes(ext)) return "image-x-generic";
    if ([ "zip", "rar", "7z", "tar", "gz", "xz" ].includes(ext)) return "package-x-generic";
    if (ext === "pdf") return "application-pdf";
    return "text-x-generic";
  }

  Column {
    anchors.centerIn: parent
    spacing: 10

    IconImage {
      anchors.horizontalCenter: parent.horizontalCenter
      implicitSize: 72
      source: Quickshell.iconPath(root.iconName, "text-x-generic")
    }

    Text {
      width: root.width - 20
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.fileName
      color: root.current ? Theme.bg : Theme.fg
      font.pixelSize: 16
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      maximumLineCount: 2
      wrapMode: Text.Wrap
    }
  }
}
