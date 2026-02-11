import QtQuick
import QtQuick.Layouts
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

    // Bar positioning properties (required for some bar logic)
    readonly property string screenName: screen ? screen.name : ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isVertical: barPosition === "left" || barPosition === "right"
    readonly property real barHeight: Style.getBarHeightForScreen(screenName)
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

    property var mainInstance: pluginApi?.mainInstance
    property var cfg: pluginApi?.pluginSettings || ({})
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})
    readonly property string iconColorKey: cfg.iconColor ?? defaults.iconColor ?? "none"
    readonly property color iconColor: Color.resolveColorKey(iconColorKey)
    
    icon: "coffee"
    
    // Style
    baseSize: root.capsuleHeight
    customRadius: Style.radiusL
    
    // Color logic: Primary when active, configured color (or default capsule color) when inactive
    colorBg: mainInstance?.isActive ? Color.mPrimary : Style.capsuleColor
    colorFg: mainInstance?.isActive ? Color.mOnPrimary : (iconColorKey === "none" ? Color.mOnSurfaceVariant : root.iconColor)
    
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    onClicked: mainInstance?.toggle()
    onRightClicked: PanelService.showContextMenu(contextMenu, root, screen)
    
    tooltipText: mainInstance?.isActive ? "Disable Coffee Mode" : "Enable Coffee Mode"

    NPopupContextMenu {
        id: contextMenu
        model: [
            {
                "label": I18n.tr("actions.widget-settings"),
                "action": "widget-settings",
                "icon": "settings"
            }
        ]
        onTriggered: action => {
            contextMenu.close();
            PanelService.closeContextMenu(screen);
            if (action === "widget-settings") {
                BarService.openPluginSettings(screen, pluginApi.manifest);
            }
        }
    }
}
