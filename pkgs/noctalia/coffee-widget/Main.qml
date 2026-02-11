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
        
        // Inhibit sleep and handle-lid-switch. 
        // We do NOT inhibit 'idle' so the screen can turn off if configured to do so by swayidle,
        // while the system remains awake.
        inhibitor.running = true;
        isActive = true;
        
        ToastService.showNotice("Coffee", "System sleep inhibited", "coffee");
    }

    function stop() {
        if (!isActive) return;
        // Quickshell Process does not have .kill(), use .signal(15) for SIGTERM
        inhibitor.signal(15); 
        isActive = false;
        ToastService.showNotice("Coffee", "System sleep enabled", "coffee");
    }

    Process {
        id: inhibitor
        // Use systemd-inhibit to block sleep
        command: ["systemd-inhibit", "--what=sleep:handle-lid-switch", "--who=NoctaliaCoffee", "--why=User requested caffeine", "--mode=block", "sleep", "infinity"]
        running: false
        
        onExited: {
            if (isActive) {
                // If it exits unexpectedly (e.g. killed externally), update state
                isActive = false;
                ToastService.showError("Coffee", "Inhibitor process exited unexpectedly");
            }
        }
    }
}
