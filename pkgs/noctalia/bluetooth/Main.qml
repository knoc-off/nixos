import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Services.System

Item {
    id: root
    property var pluginApi: null

    property bool adapterAvailable: false
    property bool adapterPowered: false
    property var devices: []
    property bool scanning: false

    readonly property var pinnedAddresses: pluginApi?.pluginSettings?.pinnedDevices || []

    Timer {
        id: pollTimer
        interval: 5000
        running: adapterAvailable
        repeat: true
        onTriggered: refresh()
    }

    Process {
        id: checkAdapter
        running: true
        command: ["sh", "-c", "bluetoothctl show 2>/dev/null | head -5"]
        stdout: StdioCollector {}
        onExited: exitCode => {
            if (exitCode === 0 && stdout.text.length > 0) {
                adapterAvailable = true
                adapterPowered = stdout.text.includes("Powered: yes")
                refresh()
            } else {
                adapterAvailable = false
            }
        }
    }

    Process {
        id: refreshProcess
        stdout: StdioCollector {}
        onExited: exitCode => {
            if (exitCode !== 0) return
            parseDevices(stdout.text)
        }
    }

    Process {
        id: actionProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: exitCode => {
            refresh()
        }
    }

    function refresh() {
        if (!adapterAvailable) return
        refreshProcess.exec({ command: ["sh", "-c", "bluetoothctl devices Paired 2>/dev/null && echo '---CONNECTED---' && bluetoothctl devices Connected 2>/dev/null"] })
    }

    function parseDevices(output) {
        var lines = output.split('\n')
        var deviceMap = {}
        var connectedAddrs = new Set()

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line === '---CONNECTED---') {
                for (var j = i + 1; j < lines.length; j++) {
                    var cline = lines[j].trim()
                    var cmatch = cline.match(/Device\s+([0-9A-Fa-f:]+)\s+(.+)/)
                    if (cmatch) connectedAddrs.add(cmatch[1])
                }
                break
            }
            var match = line.match(/Device\s+([0-9A-f:]+)\s+(.+)/)
            if (match) {
                var addr = match[1]
                var name = match[2]
                deviceMap[addr] = {
                    address: addr,
                    name: name,
                    paired: true,
                    connected: false,
                    pinned: pinnedAddresses.includes(addr)
                }
            }
        }

        var newDevices = Object.values(deviceMap)
        for (var k = 0; k < newDevices.length; k++) {
            if (connectedAddrs.has(newDevices[k].address)) {
                newDevices[k].connected = true
            }
        }

        newDevices.sort((a, b) => {
            if (a.pinned !== b.pinned) return b.pinned ? 1 : -1
            if (a.connected !== b.connected) return b.connected ? 1 : -1
            return a.name.localeCompare(b.name)
        })

        devices = newDevices
    }

    function toggleAdapter() {
        var cmd = adapterPowered ? "power off" : "power on"
        actionProcess.exec({ command: ["sh", "-c", `bluetoothctl ${cmd}`] })
        adapterPowered = !adapterPowered
        ToastService.showNotice("Bluetooth", adapterPowered ? "Bluetooth enabled" : "Bluetooth disabled", "bluetooth")
    }

    function connectDevice(address) {
        actionProcess.exec({ command: ["sh", "-c", `bluetoothctl connect ${address}`] })
    }

    function disconnectDevice(address) {
        actionProcess.exec({ command: ["sh", "-c", `bluetoothctl disconnect ${address}`] })
    }

    function toggleDevice(address) {
        var device = devices.find(d => d.address === address)
        if (!device) return
        if (device.connected) {
            disconnectDevice(address)
        } else {
            connectDevice(address)
        }
    }

    function forgetDevice(address) {
        actionProcess.exec({ command: ["sh", "-c", `bluetoothctl remove ${address}`] })
    }

    IpcHandler {
        target: "plugin:bluetooth"
        function toggleAdapter() { root.toggleAdapter() }
        function refresh() { root.refresh() }
        function connectDevice(addr) { root.connectDevice(addr) }
        function disconnectDevice(addr) { root.disconnectDevice(addr) }
        function toggleDevice(addr) { root.toggleDevice(addr) }
        function forgetDevice(addr) { root.forgetDevice(addr) }
    }
}