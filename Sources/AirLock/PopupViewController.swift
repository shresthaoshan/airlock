import AirLockCore
import AppKit
import ServiceManagement

final class PopupViewController: NSViewController, NSTextFieldDelegate {
    var onSettingsChange: ((LockSettings) -> Void)?
    var onEnabledChange: ((Bool) -> Void)?
    var onLoginChange: ((Bool) -> Void)?
    var onOpenLog: (() -> Void)?
    var onQuit: (() -> Void)?

    private var settings = LockSettings()
    private let state = NSTextField(labelWithString: "Not armed")
    private let device = NSTextField(wrappingLabelWithString: "No live AirPods")
    private let enabled = NSButton(checkboxWithTitle: "Lock When I Walk Away", target: nil, action: nil)
    private let thresholdValue = NSTextField(labelWithString: "−70 dBm")
    private let threshold = NSSlider(value: -70, minValue: -120, maxValue: -20, target: nil, action: nil)
    private let delay = NSTextField(string: "5")
    private let noSignal = NSTextField(labelWithString: "No-signal delay: 8 s")
    private let inputError = NSTextField(labelWithString: "Enter a whole number from 0 to 30.")
    private let login = NSButton(checkboxWithTitle: "Open at Login", target: nil, action: nil)
    private let loginNote = NSTextField(wrappingLabelWithString: "Approve AirLock in Login Items.")
    private let warning = NSTextField(wrappingLabelWithString:
        "Turn on “Require password immediately” in Lock Screen settings.")

    override func loadView() {
        view = NSView()
        let title = NSTextField(labelWithString: "AirLock")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        state.font = .systemFont(ofSize: 13, weight: .semibold)
        device.textColor = .secondaryLabelColor
        device.maximumNumberOfLines = 2
        device.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        enabled.target = self
        enabled.action = #selector(changeEnabled)
        threshold.target = self
        threshold.action = #selector(changeThreshold)
        threshold.numberOfTickMarks = 11
        threshold.allowsTickMarkValuesOnly = true
        threshold.isContinuous = true
        threshold.setAccessibilityLabel("Weak signal threshold in dBm")
        thresholdValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        delay.alignment = .right
        delay.delegate = self
        delay.setAccessibilityLabel("Weak signal delay in seconds, from 0 to 30")
        delay.widthAnchor.constraint(equalToConstant: 52).isActive = true
        delay.toolTip = "Enter a whole number from 0 to 30 seconds."
        login.target = self
        login.action = #selector(changeLogin)
        for label in [noSignal, inputError, loginNote, warning] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
        }
        inputError.textColor = .systemRed
        inputError.isHidden = true
        loginNote.isHidden = true
        warning.isHidden = true
        let actions = row([
            NSButton(title: "Open Log", target: self, action: #selector(openLog)),
            NSButton(title: "Quit AirLock", target: self, action: #selector(quit))
        ])
        let thresholdHeading = row([NSTextField(labelWithString: "Weak signal threshold"), thresholdValue])
        let range = row([NSTextField(labelWithString: "−120 dBm"), NSTextField(labelWithString: "−20 dBm")])
        range.arrangedSubviews.forEach { ($0 as? NSTextField)?.textColor = .secondaryLabelColor }
        let delayRow = row([NSTextField(labelWithString: "Weak signal delay"), delay, NSTextField(labelWithString: "s")])
        let stack = NSStackView(views: [title, state, device, separator(), enabled,
                                      thresholdHeading, threshold, range, delayRow, inputError,
                                      noSignal, separator(), login, loginNote, warning, separator(), actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 336),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18)
        ])
        for child in [device, thresholdHeading, threshold, range, delayRow, loginNote, warning, actions] as [NSView] {
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func row(_ controls: [NSView]) -> NSStackView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        var views = controls
        views.insert(spacer, at: 1)
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: 300).isActive = true
        return line
    }

    func update(armed: Bool, isEnabled: Bool, liveDevice: (name: String, rssi: Int)?,
                settings: LockSettings, loginStatus: SMAppService.Status) {
        loadViewIfNeeded()
        self.settings = settings
        state.stringValue = armed ? "Armed" : "Not armed"
        state.textColor = armed ? .systemGreen : .secondaryLabelColor
        device.stringValue = liveDevice.map { "\($0.name) · \($0.rssi) dBm" } ?? "No live AirPods"
        enabled.state = isEnabled ? .on : .off
        threshold.integerValue = settings.threshold
        thresholdValue.stringValue = "\(settings.threshold) dBm"
        if delay.currentEditor() == nil { delay.stringValue = String(settings.delay) }
        noSignal.stringValue = "No-signal delay: \(settings.delay + 3) s"
        switch loginStatus {
        case .enabled: login.state = .on
        case .requiresApproval: login.state = .off
        default: login.state = .off
        }
        loginNote.isHidden = loginStatus != .requiresApproval
        resizeToFit()
    }

    func showPasswordWarning(_ show: Bool) {
        loadViewIfNeeded()
        warning.isHidden = !show
        resizeToFit()
    }

    private func resizeToFit() {
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    @objc private func changeThreshold() {
        settings = LockSettings(threshold: threshold.integerValue, delay: settings.delay)
        thresholdValue.stringValue = "\(settings.threshold) dBm"
        onSettingsChange?(settings)
    }

    func controlTextDidChange(_ notification: Notification) {
        let value = Int(delay.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        inputError.isHidden = value.map { (0...30).contains($0) } ?? false
        resizeToFit()
        guard let value, (0...30).contains(value) else { return }
        settings = LockSettings(threshold: settings.threshold, delay: value)
        noSignal.stringValue = "No-signal delay: \(value + 3) s"
        onSettingsChange?(settings)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        delay.stringValue = String(settings.delay)
        inputError.isHidden = true
        resizeToFit()
    }

    @objc private func changeEnabled() { onEnabledChange?(enabled.state == .on) }
    @objc private func changeLogin() { onLoginChange?(login.state != .off) }
    @objc private func openLog() { onOpenLog?() }
    @objc private func quit() { onQuit?() }
}
