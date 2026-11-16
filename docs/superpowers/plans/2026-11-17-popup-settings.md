# Popup Settings Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task.

**Goal:** Build the agreed menu bar popup with saved threshold and delay controls.

**Architecture:** Keep lock decisions and settings validation in AirLockCore. Monitor owns Bluetooth activity and applies settings. AppKit owns the popup and login registration.

**Tech Stack:** Swift, AppKit, CoreBluetooth, ServiceManagement, Foundation, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-17-popup-settings-design.md`

## Global Constraints

- macOS 14 or later. No new dependencies. Ignore autogen.
- Threshold -120 through -20 dBm, step 10. Delay 0 through 30 whole seconds.
- No-signal delay is configured weak signal delay plus 3 seconds.
- Use the current checkout. The user requested a baseline commit before implementation; it is e48a4be.

## Review Focus

- Invalid or old saved values must produce usable controls.
- Zero delay must lock at the first qualifying decision tick.
- Changing settings must discard old pending decisions.
- Lost Bluetooth data must not leave a stale live device on screen.
- Login checkbox must reflect registration and approval state.

### Task 1: Settings and timing

**Files:** Create `Sources/AirLockCore/LockSettings.swift`; modify core tests.
**Interfaces:** `LockSettings(threshold:delay:)`, `init(defaults:)`, `save(to:)`, `rules`; `LiveSignal` tracks accepted data and expires it.

- [ ] Add failing tests for normalized settings, persistence, derived timing, endpoint arming, and signal expiry.
- [ ] Run `swift test` and confirm the new feature tests fail.
- [ ] Implement the core types and run all tests to pass.

### Task 2: Monitor and popup

**Files:** Modify Monitor.swift, System.swift, main.swift; create PopupViewController.swift.
**Interfaces:** Monitor exposes settings, live status, and `applySettings(_:)`; popup forwards control actions through closures.

- [ ] Replace startup-only settings with LockSettings and reset decision state on changes.
- [ ] Track live signals independently of whether locking is enabled; keep silence lock behavior on disconnection.
- [ ] Build the native popup with the agreed controls and login approval handling.
- [ ] Run `swift test` and `swift build -c release`.

### Task 3: Review and verification

- [ ] Review the complete diff and run the final checks.
- [ ] Inspect the native popup if UI access is available.
- [ ] Refresh Graphify and run `code-review-graph update`.
