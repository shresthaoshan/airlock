import AppKit
import ServiceManagement

/// Menu bar app: one icon, a status line, an on/off switch, the log, Quit.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor = Monitor()
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let warning = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggle = NSMenuItem(title: "Lock When I Walk Away", action: #selector(flip), keyEquivalent: "")
    private let login = NSMenuItem(title: "Open at Login", action: #selector(flipLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ note: Notification) {
        Log.write("start")
        monitor.enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
        monitor.onChange = { [weak self] in self?.refresh() }

        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        warning.isEnabled = false
        toggle.target = self
        menu.addItem(statusLine)
        menu.addItem(warning)
        menu.addItem(.separator())
        menu.addItem(toggle)
        login.target = self
        menu.addItem(login)
        menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AirLock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        let immediate = SystemInfo.screenLockIsImmediate()
        warning.title = "Turn on \"Require password immediately\" in Lock Screen settings"
        warning.isHidden = immediate
        refresh()
    }

    private func refresh() {
        statusLine.title = monitor.status
        toggle.state = monitor.enabled ? .on : .off
        switch SMAppService.mainApp.status {
        case .enabled: login.state = .on; login.title = "Open at Login"
        case .requiresApproval: login.state = .mixed; login.title = "Open at Login (approve in Login Items)"
        default: login.state = .off; login.title = "Open at Login"
        }
        let name = monitor.armed ? "lock.fill" : monitor.enabled ? "lock.open" : "lock.slash"
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "AirLock")
    }

    @objc private func flip() {
        monitor.enabled.toggle()
        UserDefaults.standard.set(monitor.enabled, forKey: "enabled")
        Log.write(monitor.enabled ? "turned on" : "turned off")
        refresh()
    }

    @objc private func flipLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled: try service.unregister(); Log.write("open at login off")
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try service.register(); Log.write("open at login on")
            }
        } catch {
            Log.write("open at login failed: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Could not change Open at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        refresh()
    }

    @objc private func openLog(){ NSWorkspace.shared.open(Log.url) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
