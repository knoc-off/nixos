// Bluetooth bar widget - shows connected devices as expanding pill
import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""

    readonly property string screenName: screen ? screen.name : ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isVertical: barPosition === "left" || barPosition === "right"

    // Only show connected devices (not paired)
    readonly property var devices: BluetoothService.connectedDevices || []

    // Hide completely when no devices connected
    implicitWidth: pill.width
    implicitHeight: pill.height
    visible: devices.length > 0
    opacity: devices.length > 0 ? 1.0 : 0.0

    Behavior on opacity { NumberAnimation { duration: Style.animationNormal } }

    BarPill {
        id: pill

        screen: root.screen
        oppositeDirection: BarService.getPillDirection(root)

        // Icon: always bluetooth-connected when we have devices
        icon: "bluetooth-connected"

        // Text: first device name (only when 2+ devices in horizontal bar)
        text: devices.length > 1 && !isVertical
            ? (devices[0].name || devices[0].deviceName || "Device")
            : ""

        // Suffix: show count when 2+ devices
        suffix: devices.length > 1 ? ` +${devices.length - 1}` : ""

        autoHide: false
        // In vertical bar OR single device: collapse to icon only
        forceClose: isVertical || devices.length === 1
        // In horizontal bar with 2+ devices: force text visible
        forceOpen: !isVertical && devices.length > 1

        tooltipText: {
            if (devices.length === 0) return ""
            return devices.map(d => d.name || d.deviceName || "Device").join(", ")
        }

        onClicked: {
            var p = PanelService.getPanel("bluetoothPanel", screen)
            if (p) p.toggle(pill)
        }

        onRightClicked: {
            var p = PanelService.getPanel("bluetoothPanel", screen)
            if (p) p.toggle(pill)
        }
    }
}
