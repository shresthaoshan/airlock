import AirLockCore
import AppKit
import Testing
@testable import AirLock

@MainActor
struct PopupTests {
    private func controls<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { controls($0, of: type) }
    }

    private func radios(_ popup: PopupViewController) -> [NSButton] {
        controls(popup.view, of: NSButton.self).filter { $0.action == Selector(("changePhone:")) }
    }

    private func popup() -> PopupViewController {
        _ = NSApplication.shared
        let popup = PopupViewController()
        popup.update(armed: false, isEnabled: true, liveDevice: nil,
                     settings: LockSettings(), loginStatus: .notRegistered)
        return popup
    }

    @Test func sizesPopupAndConfiguresSlider() throws {
        let popup = popup()
        #expect(popup.preferredContentSize.width == 336)
        #expect(popup.preferredContentSize.height > 300)
        let slider = try #require(controls(popup.view, of: NSSlider.self).first)
        #expect(slider.minValue == -120)
        #expect(slider.maxValue == -20)
        #expect(slider.numberOfTickMarks == 11)
        #expect(slider.allowsTickMarkValuesOnly)
        var applied: LockSettings?
        popup.onSettingsChange = { applied = $0 }
        slider.integerValue = -120
        NSApp.sendAction(try #require(slider.action), to: slider.target, from: slider)
        #expect(applied?.threshold == -120)
    }

    @Test func appliesValidDelayAndRejectsInvalidInput() throws {
        let popup = popup()
        let field = try #require(controls(popup.view, of: NSTextField.self).first { $0.isEditable })
        var applied: [LockSettings] = []
        popup.onSettingsChange = { applied.append($0) }
        for value in ["0", "30", "-1", "31", "1.5", "abc", ""] {
            field.stringValue = value
            popup.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        }
        #expect(applied.map(\.delay) == [0, 30])
        popup.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        #expect(field.stringValue == "30")
        #expect(controls(popup.view, of: NSTextField.self).contains { $0.stringValue == "No-signal delay: 33 s" })
    }

    @Test func reflectsLiveStateAndLoginCheckbox() throws {
        let popup = popup()
        popup.update(armed: true, isEnabled: true, liveDevice: ("Desk AirPods", -55),
                     settings: LockSettings(), loginStatus: .enabled)
        let labels = controls(popup.view, of: NSTextField.self)
        #expect(labels.contains { $0.stringValue == "Armed" })
        #expect(labels.contains { $0.stringValue.contains("Desk AirPods") })
        let login = try #require(controls(popup.view, of: NSButton.self).first { $0.title == "Open at Login" })
        #expect(login.state == .on)
        var requested: Bool?
        popup.onLoginChange = { requested = $0 }
        login.performClick(nil)
        #expect(requested == false)
        popup.update(armed: false, isEnabled: false, liveDevice: nil,
                     settings: LockSettings(), loginStatus: .requiresApproval)
        #expect(labels.contains { $0.stringValue == "Not armed" })
        #expect(labels.contains { $0.stringValue == "No live AirPods" })
        #expect(login.state == .off)
        #expect(labels.contains { $0.stringValue == "Approve AirLock in Login Items." && !$0.isHidden })
    }

    @Test func selectsSourceAndKeepsAnAbsentSavedPhone() throws {
        let popup = popup()
        let phone = PhoneDevice(id: UUID(), name: "Desk iPhone")
        popup.update(armed: false, isEnabled: true, liveDevice: nil,
                     settings: LockSettings(threshold: -60, delay: 10), loginStatus: .notRegistered,
                     source: LockSource(device: .iPhone, phone: phone), nearbyPhones: [])
        let sourceControl = try #require(controls(popup.view, of: NSSegmentedControl.self).first)
        #expect(sourceControl.selectedSegment == 1)
        let radio = try #require(radios(popup).first)
        #expect(radio.title == "Desk iPhone" && radio.state == .on)
        #expect(controls(popup.view, of: NSTextField.self).contains { $0.stringValue == "No live iPhone signal" })
        var selected: LockDevice?
        popup.onDeviceChange = { selected = $0 }
        sourceControl.selectedSegment = 0
        NSApp.sendAction(try #require(sourceControl.action), to: sourceControl.target, from: sourceControl)
        #expect(selected == .airPods)
    }

    @Test func selectsAnExactPhoneAndShowsMissingSelection() throws {
        let popup = popup()
        let first = PhoneDevice(id: UUID(), name: "Same iPhone")
        let second = PhoneDevice(id: UUID(), name: "Same iPhone")
        popup.update(armed: false, isEnabled: true, liveDevice: nil,
                     settings: LockSettings(threshold: -60, delay: 10), loginStatus: .notRegistered,
                     source: LockSource(device: .iPhone), nearbyPhones: [first, second])
        #expect(controls(popup.view, of: NSTextField.self).contains { $0.stringValue == "Select an iPhone to start." })
        #expect(controls(popup.view, of: NSTextField.self).first { $0.isEditable }?.stringValue == "10")
        let list = radios(popup)
        #expect(list.count == 2 && list.allSatisfy { $0.state == .off })
        #expect(list[0].title != list[1].title)               // duplicate names get an ID suffix
        var selected: PhoneDevice?
        popup.onPhoneChange = { selected = $0 }
        list[1].performClick(nil)
        #expect(selected == second)
    }

    @Test func preservesIdentityWhenNearbyListChanges() throws {
        let popup = popup()
        let saved = PhoneDevice(id: UUID(), name: "Saved iPhone")
        let other = PhoneDevice(id: UUID(), name: "Other iPhone")
        let source = LockSource(device: .iPhone, phone: saved)
        popup.update(armed: true, isEnabled: true, liveDevice: (saved.name, -40),
                     settings: LockSettings(threshold: -60, delay: 10), loginStatus: .notRegistered,
                     source: source, nearbyPhones: [saved])
        popup.update(armed: true, isEnabled: true, liveDevice: (saved.name, -40),
                     settings: LockSettings(threshold: -60, delay: 10), loginStatus: .notRegistered,
                     source: source, nearbyPhones: [other, saved])
        var selected: PhoneDevice?
        popup.onPhoneChange = { selected = $0 }
        try #require(radios(popup).first { $0.state == .on }).performClick(nil)
        #expect(selected == saved)
        popup.update(armed: false, isEnabled: true, liveDevice: nil,
                     settings: LockSettings(threshold: -60, delay: 10), loginStatus: .notRegistered,
                     source: source, nearbyPhones: [other])
        let checked = try #require(radios(popup).first { $0.state == .on })
        #expect(checked.title == saved.name)
        checked.performClick(nil)
        #expect(selected == saved)
    }

    @Test func menuItemSizeFollowsTheIPhoneLayout() {
        let popup = popup()
        let menu = NSMenu()
        popup.attach(to: menu)
        #expect(menu.items.count == 1)
        #expect(menu.items.first?.view === popup.view)
        let phone = PhoneDevice(id: UUID(), name: "Desk iPhone")
        popup.update(armed: true, isEnabled: true, liveDevice: (phone.name, -40),
                     settings: LockSettings(threshold: -60, delay: 10), loginStatus: .notRegistered,
                     source: LockSource(device: .iPhone, phone: phone), nearbyPhones: [phone])
        #expect(popup.view.frame.size == popup.preferredContentSize)
        #expect(popup.view.frame.height >= popup.view.fittingSize.height)
    }

    @Test func signalUpdatesDoNotResizeTheMenuItem() {
        let popup = popup()
        popup.attach(to: NSMenu())
        let phone = PhoneDevice(id: UUID(), name: "Desk iPhone")
        let source = LockSource(device: .iPhone, phone: phone)
        let settings = LockSettings(threshold: -60, delay: 10)
        popup.update(armed: true, isEnabled: true, liveDevice: (phone.name, -40),
                     settings: settings, loginStatus: .notRegistered, source: source, nearbyPhones: [phone])
        let size = popup.view.frame.size
        var changes = 0
        let observation = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: popup.view, queue: nil) { _ in changes += 1 }
        for rssi in [-39, -42, -41, -40] {
            popup.update(armed: true, isEnabled: true, liveDevice: (phone.name, rssi),
                         settings: settings, loginStatus: .notRegistered, source: source, nearbyPhones: [phone])
        }
        #expect(popup.view.frame.size == size)
        #expect(changes == 0)
        NotificationCenter.default.removeObserver(observation)
        popup.update(armed: false, isEnabled: true, liveDevice: nil,
                     settings: LockSettings(), loginStatus: .notRegistered)
        #expect(popup.view.frame.height < size.height)
        #expect(popup.view.frame.size == popup.view.fittingSize)
        popup.update(armed: true, isEnabled: true, liveDevice: (phone.name, -40),
                     settings: settings, loginStatus: .notRegistered, source: source, nearbyPhones: [phone])
        #expect(popup.view.frame.size == size)
    }
}
