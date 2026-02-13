import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services.UI
import qs.Services.System

Item {
    id: root
    property var pluginApi: null
    property bool isActive: false
    readonly property bool lockOnActivate: pluginApi?.pluginSettings?.lockOnActivate ?? true

    function toggle() {
        if (isActive) {
            stop();
        } else {
            start();
        }
    }

    function start() {
        if (isActive) return;

        if (lockOnActivate) {
             Quickshell.execDetached(["loginctl", "lock-session"]);
        }




        inhibitor.running = true;
        isActive = true;

        ToastService.showNotice("Coffee", "System sleep inhibited", "coffee");
    }

    function stop() {
        if (!isActive) return;

        inhibitor.signal(15);
        isActive = false;
        ToastService.showNotice("Coffee", "System sleep enabled", "coffee");
    }

    Process {
        id: inhibitor

        command: ["systemd-inhibit", "--what=sleep:handle-lid-switch", "--who=NoctaliaCoffee", "--why=User requested caffeine", "--mode=block", "sleep", "infinity"]
        running: false

        onExited: {
            if (isActive) {

                isActive = false;
                ToastService.showError("Coffee", "Inhibitor process exited unexpectedly");
            }
        }
    }
}
