import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
    id: root
    property var pluginApi: null

    property bool isRunning: false
    property bool isRecording: false
    property string pendingTool: ""
    property string recordingPath: ""

    readonly property string regionFile: "/tmp/screen-shot-region.txt"

    // ── IPC ───────────────────────────────────────────────────
    IpcHandler {
        target: "plugin:screen-shot"
        function screenshot() { root.runScreenshot() }
        function record()     { root.isRecording ? root.stopRecording() : root.runRecord() }
    }

    // ── Public API (called from BarWidget) ────────────────────
    function runScreenshot() {
        if (isRunning) return
        pendingTool = "screenshot"
        isRunning = true
        _launchSlurp()
    }

    function runRecord() {
        if (isRunning || isRecording) return
        pendingTool = "record"
        isRunning = true
        _launchSlurp()
    }

    function stopRecording() {
        if (!isRecording) return
        isRecording = false
        stopProc.exec({ command: ["bash", "-c", "pkill -INT wl-screenrec 2>/dev/null || true"] })
    }

    // ── Slurp via systemd-run (escapes layershell) ────────────
    function _launchSlurp() {
        clearRegionProc.exec({
            command: ["bash", "-c",
                "rm -f " + regionFile + " " + regionFile + ".cancel " + regionFile + ".tmp"
            ]
        })
        slurpProc.exec({
            command: ["bash", "-c",
                "systemd-run --user --collect --quiet " +
                "bash -c 'slurp > " + regionFile + ".tmp 2>/dev/null && " +
                "REGION=$(cat " + regionFile + ".tmp); " +
                "W=$(echo \"$REGION\" | cut -d\" \" -f2 | cut -dx -f1); " +
                "H=$(echo \"$REGION\" | cut -d\" \" -f2 | cut -dx -f2); " +
                "{ [ \"${W:-0}\" -gt 2 ] && [ \"${H:-0}\" -gt 2 ]; } && " +
                "mv " + regionFile + ".tmp " + regionFile + " || " +
                "{ rm -f " + regionFile + ".tmp; touch " + regionFile + ".cancel; }'"
            ]
        })
        _slurpPollCount = 0
        slurpPollTimer.start()
    }

    // ── Processes ─────────────────────────────────────────────
    Process { id: clearRegionProc }
    Process { id: stopProc }

    Process {
        id: slurpProc
        onExited: code => {
            if (code !== 0) {
                slurpPollTimer.stop()
                root.isRunning = false
                root.pendingTool = ""
            }
        }
    }

    Process {
        id: slurpCheckProc
        stdout: StdioCollector { id: checkOut }
        onExited: code => {
            if (code !== 0) return  // not ready yet
            var result = checkOut.text.trim()
            slurpPollTimer.stop()
            root._slurpPollCount = 0
            if (result === "cancel") {
                root.isRunning = false
                root.pendingTool = ""
            } else if (result === "ok") {
                _dispatchTool()
            }
        }
    }

    // Screenshot: grim region -> tee /tmp file -> wl-copy
    Process {
        id: screenshotProc
        onExited: code => {
            root.isRunning = false
            root.pendingTool = ""
            if (code === 0)
                ToastService.showNotice("Screenshot", "Copied to clipboard", "camera")
            else
                ToastService.showError("Screenshot failed")
        }
    }

    // Recording: wl-screenrec
    Process {
        id: recorderProc
        onExited: code => {
            root.isRecording = false
            root.isRunning = false
            root.pendingTool = ""
            if (code === 0 || code === 130 || code === 2) {
                clipProc.exec({
                    command: ["bash", "-c",
                        "printf '%s' '" + root.recordingPath + "' | wl-copy"
                    ]
                })
                ToastService.showNotice("Recording saved",
                    root.recordingPath + "  •  path copied", "video")
                dragonProc.exec({
                    command: ["dragon-drop", "--and-exit", root.recordingPath]
                })
            } else {
                ToastService.showError("Recording failed (exit " + code + ")")
            }
        }
    }

    Process {
        id: recordRegionProc
        stdout: StdioCollector { id: recRegionOut }
        onExited: code => {
            var region = recRegionOut.text.trim()
            if (code === 0 && region !== "") {
                root.isRecording = true
                recorderProc.exec({
                    command: ["wl-screenrec",
                        "--geometry", region,
                        "--filename", root.recordingPath
                    ]
                })
            } else {
                root.isRunning = false
                root.pendingTool = ""
            }
        }
    }

    Process { id: clipProc }
    Process { id: dragonProc }

    // ── Timers ────────────────────────────────────────────────
    property int _slurpPollCount: 0

    Timer {
        id: slurpPollTimer
        interval: 200; repeat: true
        onTriggered: {
            root._slurpPollCount++
            if (root._slurpPollCount > 300) {  // 60s timeout
                slurpPollTimer.stop()
                root._slurpPollCount = 0
                root.isRunning = false
                root.pendingTool = ""
                return
            }
            slurpCheckProc.exec({
                command: ["bash", "-c",
                    "if [ -f " + root.regionFile + ".cancel ]; then " +
                    "  rm -f " + root.regionFile + ".cancel; echo cancel; exit 0; " +
                    "elif [ -f " + root.regionFile + " ]; then " +
                    "  echo ok; exit 0; " +
                    "else exit 1; fi"
                ]
            })
        }
    }

    Timer {
        id: launchScreenshot
        interval: 50; repeat: false
        onTriggered: {
            var ts = Qt.formatDateTime(new Date(), "yyyyMMdd_HHmmss")
            var path = "/tmp/screenshot_" + ts + ".png"
            screenshotProc.exec({
                command: ["bash", "-c",
                    "REGION=$(cat " + root.regionFile + ") || exit 1; " +
                    "grim -g \"$REGION\" - | tee '" + path + "' | wl-copy --type image/png; " +
                    "rm -f " + root.regionFile
                ]
            })
        }
    }

    Timer {
        id: launchRecord
        interval: 50; repeat: false
        onTriggered: {
            var ts = Qt.formatDateTime(new Date(), "yyyyMMdd_HHmmss")
            var home = Quickshell.env("HOME") || ""
            root.recordingPath = home + "/Videos/recordings/recording_" + ts + ".mp4"
            recordRegionProc.exec({
                command: ["bash", "-c",
                    "mkdir -p '" + home + "/Videos/recordings' && " +
                    "cat " + root.regionFile + " && rm -f " + root.regionFile
                ]
            })
        }
    }

    // ── Internal ──────────────────────────────────────────────
    function _dispatchTool() {
        switch (root.pendingTool) {
            case "screenshot": launchScreenshot.start(); break
            case "record":     launchRecord.start();     break
            default:
                root.isRunning = false
                root.pendingTool = ""
        }
    }
}
