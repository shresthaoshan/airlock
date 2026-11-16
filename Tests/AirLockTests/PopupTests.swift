import AirLockCore
import AppKit
import Testing
@testable import AirLock

@MainActor
struct PopupTests {
    private func controls<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { controls($0, of: type) }
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
}
