// Screenshot and screen recording plugin for Noctalia
// Provides functionality to capture screenshots and record screen regions using slurp, grim, and wl-screenrec

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
    id: root
    property var pluginApi: null

    // ── Lifecycle guard ───────────────────────────────────────
    // Prevents process exit handlers from firing after the plugin is unloaded.
    property bool alive: false
    Component.onCompleted:   { alive = true;  console.log("screen-shot: Main.qml loaded") }
    Component.onDestruction: { alive = false; console.log("screen-shot: Main.qml destroyed") }

    // ── State ─────────────────────────────────────────────────
    property bool isCapturing: false
    property bool isRecording: false
    property bool isPending: false
    property string recordingPath: ""

    // ── IPC ───────────────────────────────────────────────────
    IpcHandler {
        target: "plugin:screen-shot"
        function screenshot() { root.startScreenshot() }
        function record()     { root.isRecording || root.isPending ? root.stopRecording() : root.startRecording() }
    }

    // ── Screenshot ────────────────────────────────────────────
    // Step 1: run slurp to get geometry
    function startScreenshot() {
        console.log("screen-shot: startScreenshot called, isCapturing:", isCapturing, "isRecording:", isRecording, "isPending:", isPending)
        if (isCapturing || isRecording || isPending) return
        isCapturing = true
        console.log("screen-shot: launching slurp")
        slurpForShot.exec({ command: ["slurp"] })
    }

    Process {
        id: slurpForShot
        // Note: Use id on StdioCollector to get proper LSP type inference.
        // The Process.stdout property is typed as DataStreamParser (base class),
        // so referencing stdout.text won't work with LSP even though StdioCollector
        // has the text property. Reference the collector by id instead.
        stdout: StdioCollector {
            id: shotCollector
        }
        onExited: exitCode => {
            console.log("screen-shot: slurp exited with code:", exitCode, "stdout:", shotCollector.text)
            if (!root.alive || exitCode !== 0) {
                root.isCapturing = false
                return
            }
            var geo = shotCollector.text.trim()
            if (!geo) { root.isCapturing = false; return }

            var ts = Qt.formatDateTime(new Date(), "yyyyMMdd_HHmmss")
            var path = "/tmp/screenshot_" + ts + ".png"
            grimProc.outPath = path
            console.log("screen-shot: launching grim with geo:", geo)
            grimProc.exec({
                command: ["sh", "-c",
                    "grim -g '" + geo + "' - | tee '" + path + "' | wl-copy --type image/png"
                ]
            })
        }
    }

    // Step 2: grim → tee to /tmp → wl-copy
    Process {
        id: grimProc
        property string outPath: ""
        onExited: exitCode => {
            if (!root.alive) return
            root.isCapturing = false
            if (exitCode === 0) {
                ToastService.showNotice("Screenshot", "Copied to clipboard  •  " + outPath, "camera")
            } else {
                ToastService.showError("Screenshot failed", "Check grim / wl-copy are available")
            }
        }
    }

    // ── Recording ─────────────────────────────────────────────
    // Step 1: run slurp to get region
    function startRecording() {
        if (isCapturing || isRecording || isPending) return
        isPending = true
        slurpForRec.exec({ command: ["slurp"] })
    }

    Process {
        id: slurpForRec
        stdout: StdioCollector {
            id: recCollector
        }
        onExited: exitCode => {
            console.log("screen-shot: slurpForRec exited with code:", exitCode, "stdout:", recCollector.text)
            if (!root.alive || exitCode !== 0) {
                root.isPending = false
                return
            }
            var geo = recCollector.text.trim()
            if (!geo) { root.isPending = false; return }

            var ts = Qt.formatDateTime(new Date(), "yyyyMMdd_HHmmss")
            var home = Quickshell.env("HOME") || ""
            root.recordingPath = home + "/Videos/recordings/recording_" + ts + ".mp4"

            console.log("screen-shot: mkdir with geo:", geo)
            mkdirProc.geometry = geo
            mkdirProc.exec({
                command: ["sh", "-c", "mkdir -p '" + home + "/Videos/recordings'"]
            })
        }
    }

    // Step 2: ensure output dir exists
    Process {
        id: mkdirProc
        property string geometry: ""
        onExited: exitCode => {
            if (!root.alive || exitCode !== 0) {
                root.isPending = false
                if (root.alive) ToastService.showError("Recording failed", "Cannot create output directory")
                return
            }
            recorderProc.exec({
                command: ["wl-screenrec",
                    "--geometry", mkdirProc.geometry,
                    "--filename", root.recordingPath
                ]
            })
            pendingTimer.start()
        }
    }

    // Step 3: wl-screenrec runs until stopped
    Process {
        id: recorderProc
        onExited: exitCode => {
            if (!root.alive) return
            root.isRecording = false
            root.isPending = false
            pendingTimer.stop()

            if (exitCode === 0 || exitCode === 130 || exitCode === 2) {
                Quickshell.execDetached(["sh", "-c",
                    "printf '%s' '" + root.recordingPath + "' | wl-copy"
                ])
                ToastService.showNotice(
                    "Recording saved",
                    root.recordingPath + "  •  path copied",
                    "video",
                    4000
                )
                Quickshell.execDetached(["dragon-drop", "--and-exit", root.recordingPath])
            } else {
                ToastService.showError("Recording failed", "wl-screenrec exited " + exitCode)
            }
        }
    }

    function stopRecording() {
        if (!isRecording && !isPending) return
        Quickshell.execDetached(["sh", "-c", "pkill -INT wl-screenrec || true"])
    }

    Timer {
        id: pendingTimer
        interval: 1500
        onTriggered: {
            if (root.isPending && recorderProc.running) {
                root.isPending = false
                root.isRecording = true
                ToastService.showNotice("Recording", "Recording…  click to stop", "video")
            } else if (root.isPending) {
                root.isPending = false
                ToastService.showError("Recording failed", "wl-screenrec did not start")
            }
        }
    }
}
