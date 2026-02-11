import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

ColumnLayout {
    id: root
    spacing: Style.marginL
    property var pluginApi: null

    property bool editLockOnActivate: 
        pluginApi?.pluginSettings?.lockOnActivate ?? 
        pluginApi?.manifest?.metadata?.defaultSettings?.lockOnActivate ?? 
        true
        
    property string editIconColor:
        pluginApi?.pluginSettings?.iconColor ??
        pluginApi?.manifest?.metadata?.defaultSettings?.iconColor ??
        "none"

    function saveSettings() {
        if (!pluginApi) return;
        
        pluginApi.pluginSettings.lockOnActivate = root.editLockOnActivate;
        pluginApi.pluginSettings.iconColor = root.editIconColor;
        pluginApi.saveSettings();
        
        Logger.i("Coffee", "Settings saved successfully");
    }

    // Lock on Activate Toggle
    NToggle {
        label: "Lock screen on activate"
        description: "Automatically lock the screen when enabling Coffee mode"
        checked: root.editLockOnActivate
        onToggled: root.editLockOnActivate = checked
    }
    
    NDivider {
        Layout.fillWidth: true
    }

    // Icon Color
    NComboBox {
        label: I18n.tr("common.select-icon-color")
        description: I18n.tr("common.select-color-description")
        model: Color.colorKeyModel
        currentKey: root.editIconColor
        onSelected: key => root.editIconColor = key
        minimumWidth: 200
    }
    
    Item {
        Layout.fillHeight: true
    }
}
