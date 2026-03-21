import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

NIconButton {
    id: root

    property var pluginApi: null
    property ShellScreen screen

    readonly property var main: pluginApi ? pluginApi.mainInstance : null

    icon: (main && (main.isRecording)) ? "player-stop" : "camera"

    tooltipText: {
        if (main && main.isRecording) return "Recording…  click to stop"
        if (main && main.isRunning) return "Selecting region…"
        return "Screenshot  •  right-click: record"
    }
    tooltipDirection: BarService.getTooltipDirection(screen?.name)

    colorBg: (main && main.isRecording) ? (Color.mError || "#f44336") : Style.capsuleColor
    colorFg: (main && main.isRecording) ? (Color.mOnError || "#ffffff") : Color.mOnSurfaceVariant
    colorBorder: "transparent"
    colorBorderHover: "transparent"
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    // Pulse while recording
    SequentialAnimation on opacity {
        running: main ? main.isRecording : false
        loops: Animation.Infinite
        NumberAnimation { to: 0.5; duration: 600 }
        NumberAnimation { to: 1.0; duration: 600 }
    }

    onClicked: {
        if (!main) return
        if (main.isRecording) {
            main.stopRecording()
        } else {
            main.runScreenshot()
        }
    }

    onRightClicked: {
        if (!main) return
        if (main.isRecording) {
            main.stopRecording()
        } else {
            main.runRecord()
        }
    }
}
