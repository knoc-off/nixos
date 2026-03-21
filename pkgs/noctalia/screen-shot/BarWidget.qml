import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Services.System
import qs.Widgets

NIconButton {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""

    // Access mainInstance directly at call-time — binding on pluginApi?.mainInstance
    // evaluates once before mainInstance is populated and never re-evaluates.
    function mainInstance() { return pluginApi ? pluginApi.mainInstance : null }

    readonly property bool recording: mainInstance()?.isRecording ?? false
    readonly property bool pending:   mainInstance()?.isPending   ?? false

    icon: (recording || pending) ? "video" : "camera"

    tooltipText: {
        if (recording) return "Recording…  click to stop"
        if (pending)   return "Starting recording…"
        return "Screenshot to clipboard  •  right-click for more"
    }
    tooltipDirection: BarService.getTooltipDirection()

    // For a vertical bar the BarWidgetLoader sets item.width = barHeight.
    // baseSize drives both implicitWidth and implicitHeight in NIconButton.
    // Use Style.baseWidgetSize as fallback so the widget is never 0-sized
    // before screen is injected.
    baseSize: Style.baseWidgetSize
    applyUiScale: false
    customRadius: Style.radiusL

    colorBg: (recording || pending) ? Color.mError : Style.capsuleColor
    colorFg: (recording || pending) ? Color.mOnError : Color.mOnSurfaceVariant
    colorBorder: "transparent"
    colorBorderHover: "transparent"
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    SequentialAnimation on opacity {
        running: recording
        loops: Animation.Infinite
        NumberAnimation { to: 0.5; duration: 600 }
        NumberAnimation { to: 1.0; duration: 600 }
    }

    onClicked: {
        var m = mainInstance()
        console.log("screen-shot BarWidget: clicked, mainInstance:", m)
        if (!m) return
        if (m.isRecording || m.isPending) {
            m.stopRecording()
        } else {
            m.startScreenshot()
        }
    }

    onRightClicked: {
        PanelService.showContextMenu(contextMenu, root, screen)
    }

    NPopupContextMenu {
        id: contextMenu

        model: (root.recording || root.pending)
            ? [{ label: "Stop Recording", action: "stop-record", icon: "player-stop" }]
            : [
                { label: "Screenshot to Clipboard", action: "screenshot", icon: "camera" },
                { label: "Record Region",           action: "record",     icon: "video"  }
              ]

        onTriggered: action => {
            contextMenu.close()
            PanelService.closeContextMenu(screen)
            var m = mainInstance()
            if (!m) return
            if (action === "screenshot")       m.startScreenshot()
            else if (action === "record")      m.startRecording()
            else if (action === "stop-record") m.stopRecording()
        }
    }
}
