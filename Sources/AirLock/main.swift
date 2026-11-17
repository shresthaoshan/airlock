import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor = Monitor()
    private let menu = NSMenu()
    private let popup = PopupViewController()

    func applicationDidFinishLaunching(_ note: Notification) {
        Log.write("start")
        monitor.enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
        monitor.onChange = { [weak self] in self?.refresh() }
        menu.delegate = self
        popup.attach(to: menu)
        item.menu = menu
        item.button?.toolTip = "AirLock"
        popup.onSettingsChange = { [weak self] in self?.monitor.applySettings($0) }
        popup.onDeviceChange = { [weak self] in self?.monitor.selectDevice($0) }
        popup.onPhoneChange = { [weak self] in self?.monitor.selectPhone($0) }
        popup.onEnabledChange = { [weak self] in
            self?.monitor.enabled = $0
            UserDefaults.standard.set($0, forKey: "enabled")
            Log.write($0 ? "turned on" : "turned off")
        }
        popup.onLoginChange = { [weak self] in self?.changeLogin(enabled: $0) }
        popup.onOpenLog = { NSWorkspace.shared.open(Log.url) }
        popup.onQuit = { NSApp.terminate(nil) }
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
        monitor.refreshTarget()
        DispatchQueue.global(qos: .utility).async {
            let show = !SystemInfo.screenLockIsImmediate()
            DispatchQueue.main.async { [weak self] in self?.popup.showPasswordWarning(show) }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        popup.view.window?.endEditing(for: nil)
    }

    private func refresh() {
        popup.update(armed: monitor.armed, isEnabled: monitor.enabled, liveDevice: monitor.liveDevice,
                     settings: monitor.settings, loginStatus: SMAppService.mainApp.status,
                     source: monitor.source, nearbyPhones: monitor.nearbyPhones)
        let name = monitor.armed ? "lock.fill" : monitor.enabled ? "lock.open" : "lock.slash"
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "AirLock")
    }

    private func changeLogin(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .requiresApproval {
                    menu.cancelTracking()
                    SMAppService.openSystemSettingsLoginItems()
                } else {
                    try service.register()
                    if service.status == .requiresApproval {
                        menu.cancelTracking()
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            } else {
                try service.unregister()
            }
            Log.write("open at login \(enabled ? "on" : "off")")
        } catch {
            Log.write("open at login failed: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Could not change Open at Login"
            alert.informativeText = error.localizedDescription
            menu.cancelTracking()
            alert.runModal()
        }
        refresh()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
