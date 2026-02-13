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

    property string editAudioSource: pluginApi?.pluginSettings?.audioSource ?? "both"
    property string editCodec: pluginApi?.pluginSettings?.codec ?? "opus"
    property string editBitrate: pluginApi?.pluginSettings?.bitrate ?? "128k"
    property string editDirectory: pluginApi?.pluginSettings?.directory ?? ""
    property string editFilenamePattern: pluginApi?.pluginSettings?.filenamePattern ?? "audio_yyyyMMdd_HHmmss"
    property bool editHideInactive: pluginApi?.pluginSettings?.hideInactive ?? false
    property string editIconColor: pluginApi?.pluginSettings?.iconColor ?? "none"

    function saveSettings() {
        if (!pluginApi) return
        pluginApi.pluginSettings.audioSource = root.editAudioSource
        pluginApi.pluginSettings.codec = root.editCodec
        pluginApi.pluginSettings.bitrate = root.editBitrate
        pluginApi.pluginSettings.directory = root.editDirectory
        pluginApi.pluginSettings.filenamePattern = root.editFilenamePattern
        pluginApi.pluginSettings.hideInactive = root.editHideInactive
        pluginApi.pluginSettings.iconColor = root.editIconColor
        pluginApi.saveSettings()
    }


    NComboBox {
        Layout.fillWidth: true
        label: "Audio Source"
        description: "Select what to record"
        model: [
            { key: "output", name: "System Output (What you hear)" },
            { key: "input", name: "Microphone Input" },
            { key: "both", name: "Both (Input + Output mixed)" }
        ]
        currentKey: root.editAudioSource
        onSelected: key => root.editAudioSource = key
    }

    NDivider { Layout.fillWidth: true }


    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NComboBox {
            Layout.fillWidth: true
            label: "Format"
            model: [
                { key: "opus", name: "Opus (.ogg)" },
                { key: "flac", name: "FLAC (.flac)" },
                { key: "wav", name: "WAV (.wav)" },
                { key: "mp3", name: "MP3 (.mp3)" }
            ]
            currentKey: root.editCodec
            onSelected: key => root.editCodec = key
        }

        NComboBox {
            Layout.fillWidth: true
            label: "Bitrate"
            visible: root.editCodec === "opus" || root.editCodec === "mp3"
            model: [
                { key: "64k", name: "64 kbps" },
                { key: "128k", name: "128 kbps" },
                { key: "192k", name: "192 kbps" },
                { key: "256k", name: "256 kbps" },
                { key: "320k", name: "320 kbps" }
            ]
            currentKey: root.editBitrate
            onSelected: key => root.editBitrate = key
        }
    }

    NDivider { Layout.fillWidth: true }


    NTextInput {
        label: "Filename Pattern"
        placeholderText: "audio_yyyyMMdd_HHmmss"
        text: root.editFilenamePattern
        onTextChanged: root.editFilenamePattern = text
        Layout.fillWidth: true
    }

    NTextInputButton {
        Layout.fillWidth: true
        label: "Output Directory"
        placeholderText: Quickshell.env("HOME") + "/Music"
        text: root.editDirectory
        buttonIcon: "folder-open"
        onInputEditingFinished: root.editDirectory = text
        onButtonClicked: folderPicker.openFilePicker()
    }

    NDivider { Layout.fillWidth: true }


    NToggle {
        label: "Hide when Inactive"
        description: "Hide the widget from the bar when not recording"
        checked: root.editHideInactive
        onToggled: root.editHideInactive = checked
    }

    NComboBox {
        Layout.fillWidth: true
        label: I18n.tr("common.select-icon-color")
        model: Color.colorKeyModel
        currentKey: root.editIconColor
        onSelected: key => root.editIconColor = key
    }

    Item { Layout.fillHeight: true }

    NFilePicker {
        id: folderPicker
        selectionMode: "folders"
        title: "Select Output Directory"
        initialPath: root.editDirectory || Quickshell.env("HOME") + "/Music"
        onAccepted: paths => { if (paths.length > 0) root.editDirectory = paths[0] }
    }
}
