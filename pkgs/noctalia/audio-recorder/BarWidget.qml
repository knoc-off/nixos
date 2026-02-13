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


    readonly property string screenName: screen ? screen.name : ""
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)

    readonly property var mainInstance: pluginApi?.mainInstance

    property var cfg: pluginApi?.pluginSettings || ({})
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})
    readonly property string iconColorKey: cfg.iconColor ?? defaults.iconColor ?? "none"
    readonly property color iconColor: Color.resolveColorKey(iconColorKey)
    readonly property bool hideInactive: cfg.hideInactive ?? defaults.hideInactive ?? false

    readonly property bool shouldShow: !hideInactive || (mainInstance?.isRecording ?? false) || (mainInstance?.isPending ?? false)

    visible: true
    opacity: shouldShow ? 1.0 : 0.0
    implicitWidth: shouldShow ? baseSize : 0
    implicitHeight: shouldShow ? baseSize : 0

    Behavior on opacity { NumberAnimation { duration: Style.animationNormal } }
    Behavior on implicitWidth { NumberAnimation { duration: Style.animationNormal } }
    Behavior on implicitHeight { NumberAnimation { duration: Style.animationNormal } }

    enabled: mainInstance?.isAvailable ?? false
    icon: "microphone"
    tooltipText: {
        if (!enabled) return "ffmpeg not available"
        if (mainInstance?.isRecording) return "Recording... (click to stop)"
        if (mainInstance?.isPending) return "Starting..."
        return "Start Audio Recording"
    }
    tooltipDirection: BarService.getTooltipDirection()

    baseSize: root.capsuleHeight
    applyUiScale: false
    customRadius: Style.radiusL

    colorBg: (mainInstance?.isRecording || mainInstance?.isPending) ? Color.mError : Style.capsuleColor
    colorFg: (mainInstance?.isRecording || mainInstance?.isPending) ? Color.mOnError : (iconColorKey === "none" ? Color.mOnSurfaceVariant : root.iconColor)
    colorBorder: "transparent"
    colorBorderHover: "transparent"
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    onClicked: {
        if (!enabled) {
            ToastService.showError("Audio Recorder", "ffmpeg or pactl not found")
            return
        }
        if (mainInstance) {
            mainInstance.toggle()
        }
    }

    onRightClicked: {
        PanelService.showContextMenu(contextMenu, root, screen)
    }

    NPopupContextMenu {
        id: contextMenu

        model: [
            {
                "label": (mainInstance?.isRecording || mainInstance?.isPending) ? "Stop Recording" : "Start Recording",
                "action": "toggle",
                "icon": (mainInstance?.isRecording || mainInstance?.isPending) ? "player-stop" : "player-record"
            },
            {
                "label": I18n.tr("actions.widget-settings"),
                "action": "widget-settings",
                "icon": "settings"
            }
        ]

        onTriggered: action => {
            contextMenu.close()
            PanelService.closeContextMenu(screen)

            if (action === "toggle" && mainInstance) {
                mainInstance.toggle()
            } else if (action === "widget-settings") {
                BarService.openPluginSettings(screen, pluginApi.manifest)
            }
        }
    }
}
