# Experimental iPhone Mode Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement the tasks in this session.

**Goal:** Add an optional iPhone source using the tested passive Bluetooth method.
**Architecture:** LockSource stores source and exact phone identity. LockSettings stores separate profiles. Monitor routes accepted advertisements through the existing Decider. Popup supplies source and phone selectors.
**Tech Stack:** Swift, CoreBluetooth, AppKit, Swift Testing. No new dependencies.
**Spec:** docs/superpowers/specs/2026-11-17-iphone-mode-design.md

## Global Constraints

- Ignore autogen. Keep the current checkout and existing diagnostic tools.
- One selected source controls locking. Default is AirPods.
- iPhone defaults: -60 dBm, 10-second weak delay, 13-second no-signal delay.
- Never replace a selected phone based on a matching name.

## Review Focus

- Other devices must not arm or refresh the selected phone's silence timer.
- Source and phone changes must reset pending decisions and live status.
- AirPods discovery must not reset an iPhone decision.
- Separate settings must survive switching and restart.
- A saved but absent phone must remain selected and visible.

### Task 1: Core identity and settings

- [ ] Write and run failing tests for LockSource persistence, exact identity matching, missing or invalid selection, and separate LockSettings profiles.
- [ ] Implement LockSource, PhoneDevice, and LockDevice. Extend LockSettings storage while preserving the existing AirPods keys.
- [ ] Run swift test and confirm the core tests pass.

### Task 2: Scanner and popup

- [ ] Write failing popup tests for source switching, phone selection, missing selection, absent saved phone, and iPhone defaults.
- [ ] Add passive phone discovery and exact identifier routing in Monitor. Reset decisions on source, selected phone, and setting changes.
- [ ] Add selectors, experimental note, and source-specific status to the popup. Wire actions in AppDelegate.
- [ ] Update the Bluetooth purpose text and run swift test and make app.

### Task 3: Review and verification

- [ ] Review the complete feature with a separate reviewer and fix important issues.
- [ ] Run the full tests, release build, signing check, and diff check.
- [ ] Refresh local graph outputs and run code-review-graph update.
