# Contributing to AirLock

Thank you for your help. This guide explains how to set up the project, how the code is organized, and how to send a change.

## Before you start

- For a bug fix or a small change, you can open a pull request directly.
- For a new feature, a new lock device, or a change to the lock rules, open an issue first. Then we can agree on the design before you write code.
- Do not add a new dependency without discussion in an issue. AirLock has no dependencies, and we want to keep it that way.
- AirLock is minimal on purpose. A feature that most users do not need is likely to be declined.

## Set up

You need macOS 14 or later and Xcode 16 or later.

```bash
git clone https://github.com/shresthaoshan/airlock.git
cd airlock
swift build
swift test
make run
```

`make run` builds `AirLock.app`, signs it ad hoc and opens it. If AirLock is already running, quit it first (menu › **Quit AirLock**).

Use `make run`, not `swift run`. Without the `.app` bundle, the app has no `Info.plist` and no Bluetooth usage text, so macOS stops the process when it uses Bluetooth.

## How the code works

```
CBCentralManager ──advertisement──▶ Monitor ──match──▶ Decider.observe ──▶ .armed / .disarmed
                                       │                                    
                    1 s timer ─────────┴────────────▶ Decider.tick ──▶ .lock ──▶ Locker.lock (pmset)
                                       │
system_profiler (60 s, menu open) ─────┘ AirPods target

NSStatusItem ──▶ NSMenu ──▶ one item ──▶ PopupViewController.view
```

1. `AirLockCore` has the logic and no AppKit. It is easy to test.
   - `Advert` parses an AirPods proximity pairing advertisement. `Target` matches it to the connected AirPods.
   - `Decider` turns readings into arm, disarm and lock events. `PeerPicker` follows one rotating AirPods address.
   - `LockSettings` holds the threshold and delay and makes the `Rules`. `LiveSignal` holds the last reading for the menu.
   - `LockSource` holds the lock device and the selected iPhone.
2. `AirLock` is the app.
   - `main.swift` owns the status item, the menu and the `Monitor`, and handles **Open at Login**.
   - `Monitor` runs the Bluetooth scan, feeds the `Decider` and calls `Locker.lock()`.
   - `PopupViewController` shows the controls and sends changes back through closures.
   - `System.swift` runs `system_profiler`, `sysadminctl` and `pmset`, and writes the log.
3. `Tools/` has the feasibility probes that measured the signals. They are not part of the app.

### Rules

- The lock rules live in `Decider` and `LockSettings`, not in the app target.
- Each lock must log its reason with `LOCK:`.
- Do not connect to, pair with, or send data to a Bluetooth device.
- Timers must run in `.common` run loop modes. Otherwise they stop while the menu is open, and AirLock cannot lock.
- Controls in the menu must work inside menu tracking. Do not use `NSPopUpButton` or `NSPopover`. See [DESIGN.md](DESIGN.md).
- AirLock must ask only for Bluetooth access. A change that needs another permission must be optional and off by default.

## Tests

- `swift test` must pass before you send a pull request. CI runs it on each push and pull request.
- For a bug fix, add a test that fails before the fix.
- A change to the lock rules must keep `RecordedWalkTests` green. It replays a real walk: arm at the desk, one lock at 3 m, arm again after the return. If you have a new recording that shows a problem, add it as a test.
- Tests must not change real system state: no Bluetooth scan, no lock, no real login item.

### Test in the running app

Unit tests cannot check Bluetooth, the menu bar or a real walk. Before you send a change:

1. Quit AirLock, then run `make run`. Allow Bluetooth access.
2. Open the menu at your desk. Check the live signal and that the icon becomes `lock.fill`.
3. Walk away. The Mac must lock. Come back and check that AirLock arms again.
4. Sit at the Mac for 5 minutes. It must not lock.
5. For AirPods, put the earbuds in the case. AirLock must disarm and not lock.
6. For a menu change, open the menu over a full-screen app. The menu bar must stay visible, and each control must work.
7. Read `~/Library/Logs/AirLock.log` for the reasons.

In the pull request, write which Mac, which macOS version and which device you used.

## Code style

- For the menu and the lock rules, follow [DESIGN.md](DESIGN.md).
- Match the code around your change: names, comment density, and idioms.
- Keep changes small. Prefer the standard library and system frameworks to new code.
- Write comments that explain **why**, not what.
- No compiler warnings.

## AI-assisted contributions

You can use AI tools, such as coding assistants, to write code, tests, or documentation. AirLock itself was built with AI assistance.

- **Disclose it.** In the pull request, say which parts an AI tool wrote or changed.
- **You are responsible for the change.** Read, understand, and test every line before you send it. You must be able to explain the change in review.
- **Test in the running app.** An AI tool cannot walk away from your Mac. Changes must be tested as described in [Test in the running app](#test-in-the-running-app).
- **No unreviewed output.** Pull requests and bug reports that look like unreviewed AI output are closed without review.

## Commits and pull requests

- One change for each pull request.
- Commit subject: [Conventional Commits](https://www.conventionalcommits.org/) in the imperative mood, for example `feat: add signal history` or `fix: keep timers running while the menu is open`. Use the body for details.
- For a commit that changes only documentation, add `[skip ci]` to the subject.
- In the pull request, describe what changed, why, and how you tested it.

## Report a bug

Open an issue with:

- Your macOS version, Mac model and lock device.
- The AirLock version or commit.
- Your threshold and delay.
- The steps to reproduce, what you expected, and what happened.
- The lines from `~/Library/Logs/AirLock.log` around the problem. Remove device names first.

## License

AirLock uses the [MIT License](LICENSE). When you send a pull request, you agree that your contribution is released under the same license.
