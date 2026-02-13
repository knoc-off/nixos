import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Services.System

Item {
    id: root
    property var pluginApi: null


    property bool isRecording: false
    property bool isPending: false
    property bool isAvailable: false
    property string outputPath: ""


    property string outputDevice: ""
    property string inputDevice: ""


    readonly property string audioSource: pluginApi?.pluginSettings?.audioSource ?? "both"
    readonly property string codec: pluginApi?.pluginSettings?.codec ?? "opus"
    readonly property string bitrate: pluginApi?.pluginSettings?.bitrate ?? "128k"
    readonly property string directory: pluginApi?.pluginSettings?.directory ?? ""
    readonly property string filenamePattern: pluginApi?.pluginSettings?.filenamePattern ?? "audio_yyyyMMdd_HHmmss"


    Process {
        id: checker
        running: true
        command: ["sh", "-c", "command -v ffmpeg"]
        onExited: exitCode => {
            if (exitCode === 0) {

                deviceDiscovery.running = true
            } else {
                isAvailable = false
            }
        }
    }


    Process {
        id: deviceDiscovery
        running: false
        command: ["ffmpeg", "-sources", "pulse"]
        stdout: StdioCollector {}
        onExited: exitCode => {
            if (exitCode === 0) {
                var lines = stdout.text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim()

                    if (line.includes(".monitor") && !outputDevice) {
                        var match = line.match(/^\*?\s*(\S+\.monitor)/)
                        if (match) outputDevice = match[1]
                    }

                    if (line.includes("alsa_input") && !inputDevice) {
                        var match2 = line.match(/^\*?\s*(\S+)/)
                        if (match2) inputDevice = match2[1]
                    }
                }
                console.log("Audio Recorder: Output device:", outputDevice)
                console.log("Audio Recorder: Input device:", inputDevice)
                isAvailable = (outputDevice !== "" || inputDevice !== "")
            } else {
                isAvailable = false
            }
        }
    }


    IpcHandler {
        target: "plugin:audio-recorder"
        function toggle() { root.toggle() }
        function start() { root.start() }
        function stop() { root.stop() }
    }

    function toggle() {
        if (isRecording || isPending) {
            stop()
        } else {
            start()
        }
    }

    function start() {
        if (!isAvailable) {
            ToastService.showError("Audio Recorder", "Audio devices not available")
            return
        }
        if (isRecording || isPending) return

        isPending = true
        outputPath = buildOutputPath()


        var dir = outputPath.substring(0, outputPath.lastIndexOf("/"))
        dirChecker.exec({
            command: ["sh", "-c", `mkdir -p "${dir}"`]
        })
    }

    function launchRecording() {
        var cmd = buildFFmpegCommand()
        console.log("Audio Recorder: Starting with command:", cmd)
        recorder.exec({
            command: ["sh", "-c", cmd]
        })
        pendingTimer.running = true
    }

    function stop() {
        if (!isRecording && !isPending) return

        recorder.signal(2)
        isRecording = false
        isPending = false
        pendingTimer.running = false

        ToastService.showNotice("Audio Recorder", "Saved: " + outputPath, "microphone", 3000, "Open", () => openFile(outputPath))
    }

    function openFile(path) {
        if (path) {
            Quickshell.execDetached(["xdg-open", path])
        }
    }

    function buildOutputPath() {
        var dir = Settings.preprocessPath(directory)
        if (!dir) {
            dir = Quickshell.env("HOME") + "/Music"
        }
        if (!dir.endsWith("/")) dir += "/"

        var now = new Date()
        var filename = Qt.formatDateTime(now, filenamePattern || "audio_yyyyMMdd_HHmmss")

        var ext = "ogg"
        if (codec === "flac") ext = "flac"
        else if (codec === "wav") ext = "wav"
        else if (codec === "mp3") ext = "mp3"

        return dir + filename + "." + ext
    }

    function buildFFmpegCommand() {
        var codecFlags = ""
        if (codec === "opus") codecFlags = "-c:a libopus -b:a " + bitrate
        else if (codec === "flac") codecFlags = "-c:a flac"
        else if (codec === "wav") codecFlags = "-c:a pcm_s16le"
        else if (codec === "mp3") codecFlags = "-c:a libmp3lame -b:a " + bitrate

        var input = ""
        var mapping = ""

        if (audioSource === "output") {

            input = `-f pulse -i "${outputDevice}"`
        } else if (audioSource === "input") {

            input = `-f pulse -i "${inputDevice}"`
        } else {

            input = `-f pulse -i "${outputDevice}" -f pulse -i "${inputDevice}"`
            mapping = "-map 0:a -map 1:a"
        }

        return `ffmpeg -y ${input} ${mapping} ${codecFlags} "${outputPath}"`
    }


    Process {
        id: dirChecker
        onExited: exitCode => {
            if (exitCode === 0) {
                launchRecording()
            } else {
                isPending = false
                ToastService.showError("Audio Recorder", "Cannot create output directory")
            }
        }
    }


    Process {
        id: recorder
        stderr: StdioCollector {}
        onExited: exitCode => {
            if (isRecording) {
                isRecording = false
                if (exitCode === 0) {
                    ToastService.showNotice("Audio Recorder", "Saved: " + outputPath, "microphone", 3000, "Open", () => openFile(outputPath))
                } else {
                    console.log("Audio Recorder error:", stderr.text)
                }
            }
            isPending = false
        }
    }


    Timer {
        id: pendingTimer
        interval: 1500
        running: false
        onTriggered: {
            if (isPending && recorder.running) {
                isPending = false
                isRecording = true
                ToastService.showNotice("Audio Recorder", "Recording started", "microphone")
            } else if (isPending) {
                isPending = false
                console.log("Audio Recorder: Failed to start, stderr:", recorder.stderr?.text)
                ToastService.showError("Audio Recorder", "Failed to start recording")
            }
        }
    }
}
