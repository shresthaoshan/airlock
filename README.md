# AirLock

Lock your Mac when you walk away. AirLock lives in the menu bar and follows the Bluetooth signal of your AirPods or your iPhone. When the signal becomes weak or stops, AirLock locks the Mac.

**Website:** [airlock.shresthaoshan.com](https://airlock.shresthaoshan.com/)

- No dependencies. Swift and AppKit only.
- No pairing and no connection. AirLock only listens to Bluetooth LE advertisements.
- No network. Nothing leaves your Mac.

## Why AirLock

You stand up for a coffee and forget to lock the Mac. Your screen stays open for everybody.

Your AirPods or your iPhone go where you go. AirLock uses them as a key: when they go away from the Mac, the Mac locks.

## Features

- **Lock on walk away.** Locks when the signal stays weak, or when no signal arrives.
- **AirPods.** Finds the AirPods connected to this Mac. Does not lock when you take the earbuds out or put them in the case.
- **iPhone (experimental).** Follows the iPhone that you select from nearby Apple devices.
- **Settings for each device.** Weak signal threshold (−120 to −20 dBm) and delay (0 to 30 s).
- **Live status.** The menu shows the armed state, the device and its signal.
- **Works over full-screen apps.** The menu keeps the menu bar visible.
- **Open at Login.**

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later, to build (Swift 6 tools)
- AirPods, or an iPhone with Bluetooth on
- **Require password immediately** after the screen saver begins or the display is turned off (System Settings › Lock Screen). AirLock locks the Mac by turning the display off.

## Install

AirLock has no prebuilt release yet. Build it from source:

```bash
git clone https://github.com/shresthaoshan/airlock.git
cd airlock
make app
mv AirLock.app /Applications/
open /Applications/AirLock.app
```

The lock icon appears in the menu bar. AirLock has no Dock icon.

## Build from source

```bash
make run
```

`make run` builds a release binary, puts it in `AirLock.app`, signs it ad hoc and opens it. Other targets:

| Command      | What it does                               |
|--------------|--------------------------------------------|
| `make app`   | Builds `AirLock.app` and does not open it. |
| `make test`  | Runs the tests (`swift test`).             |
| `make clean` | Removes `.build` and `AirLock.app`.        |

### Signing

`make app` signs the app ad hoc (`codesign --sign -`). This is enough to run AirLock on your own Mac.

An ad hoc signature changes with each build. macOS uses the signature to identify the app, so after a rebuild macOS asks for Bluetooth access again, and you may need to turn **Open at Login** off and on again.
For a stable signature, sign with an Apple Development certificate. Then change the `codesign` line in the `Makefile`:

```make
codesign --force --sign "Apple Development" $(APP)
```

### Permissions

AirLock needs only Bluetooth access. macOS asks the first time AirLock starts.
Without Bluetooth access, AirLock sees no signal and does not arm, so it never locks.

**Open at Login** can need your approval in System Settings › General › Login Items. AirLock opens that page when macOS asks for approval.

## Usage

Click the menu-bar icon to open the menu.

| Icon | State |
|---|---|
| `lock.fill` | Armed: AirLock locks when you walk away. |
| `lock.open` | On, but not armed yet. |
| `lock.slash` | **Lock When I Walk Away** is off. |

### How it decides

1. **Arm.** AirLock arms when the signal median stays at or above the threshold + 2 dB for 5 s. You must be near the Mac.
2. **Lock.** When armed, AirLock locks if:
   - the signal median stays below the threshold for the weak signal delay, or
   - no signal arrives for the delay + 3 s (the no-signal delay).
3. **After a lock.** AirLock arms again only when you are near the Mac again.

The median covers the last 5 s of readings, so one weak reading does not lock the Mac.

With AirPods, AirLock disarms when both earbuds are out of your ears. Then the case or the desk does not lock the Mac.

### Settings

| Setting | AirPods default | iPhone default |
|---|---|---|
| Weak signal threshold | −60 dBm | −60 dBm |
| Weak signal delay | 5 s | 10 s |

A higher threshold (for example −50) locks sooner, closer to the Mac. A lower threshold (for example −80) locks later, farther away. To find a good value, open the menu at your desk and read the live signal. Set the threshold about 5–10 dB below it.

### iPhone (experimental)

1. Select **iPhone** in **Lock device**. The menu marks iPhone mode as experimental.
2. Select your iPhone in the list of nearby devices.

AirLock follows only that iPhone. It never chooses another device by name or by signal. If the iPhone stops being detected, select it again.

## Privacy

- AirLock does not connect to, pair with, or send anything to your devices. It reads advertisements that they send to all nearby devices.
- AirLock has no network code.
- AirLock saves its settings and the selected iPhone (name and Bluetooth identifier) in `UserDefaults`.
- AirLock writes a log to `~/Library/Logs/AirLock.log`. The log contains device names, signal values and the reason for each lock.

## Known limitations

- Bluetooth signal strength is not a distance. Your body, walls and the position of the Mac change it. A threshold that works at one desk can fail at another.
- A threshold close to your desk signal locks sooner, but it can also lock while you sit at the Mac. Read the reason in the log, and lower the threshold if this happens.
- AirLock locks by turning the display off (`pmset displaysleepnow`). Without **Require password immediately**, this does not lock the Mac. The menu shows a warning in that case.
- AirLock follows the first AirPods that System Information lists as connected.
- iPhone mode is experimental. Sleep and wake, a restart of AirLock, and how long the iPhone Bluetooth identifier stays the same are not fully tested.
- The iPhone list can show other named Apple devices, such as an iPad, a Mac or an Apple Watch.

## Troubleshooting

**AirLock locks while I am at the Mac.**
Open the log and read the `LOCK:` line. If it says "signal … below …", lower the threshold by 10 dB. If it says "no signal for … s", increase the delay.

**AirLock does not lock when I walk away.**
Check that the icon is `lock.fill` before you leave. If it stays `lock.open`, AirLock did not arm: your desk signal is below the threshold + 2 dB. Lower the threshold.

**The menu says "No live AirPods".**
Connect the AirPods to this Mac and put at least one earbud in. Check Bluetooth access in System Settings › Privacy & Security › Bluetooth.

**The Mac goes dark but does not ask for a password.**
Turn on **Require password immediately** in System Settings › Lock Screen.

**macOS asks for Bluetooth access again after a rebuild.**
The ad hoc signature changed. Allow access again, or sign with a stable certificate (see [Signing](#signing)).

**Open at Login does not work.**
Move `AirLock.app` to `/Applications`, then turn the option off and on. If macOS opens Login Items, approve AirLock there.

## Uninstall

1. Open the menu and turn off **Open at Login**.
2. Click **Quit AirLock**.
3. Delete `AirLock.app`.
4. Delete the settings and the log:

```bash
defaults delete com.shresthaoshan.airlock
```

```bash
rm ~/Library/Logs/AirLock.log
```

5. Optional: remove Bluetooth access:

```bash
tccutil reset BluetoothAlways com.shresthaoshan.airlock
```

## Project structure

```
Sources/AirLockCore/
  Advert.swift              AirPods advertisement parser and target matching
  Decider.swift             Arm and lock rules, signal median, peer picker
  LockSettings.swift        Threshold and delay, saved settings, live signal
  LockSource.swift          Lock device and selected iPhone
Sources/AirLock/
  main.swift                App entry, menu-bar icon, menu, Open at Login
  Monitor.swift             Bluetooth LE scan, device matching, lock decisions
  PopupViewController.swift The controls in the menu
  System.swift              System Information lookup, lock, log
Tests/                      Swift Testing tests for the core rules and the controls
Tools/                      Feasibility probes for Bluetooth signals (not part of the app)
Info.plist                  App bundle settings (menu bar only, Bluetooth usage text)
Makefile                    Build, run and test commands
```

## Contributing

Bug reports, ideas and pull requests are welcome. Read [CONTRIBUTING.md](https://github.com/shresthaoshan/airlock/blob/main/CONTRIBUTING.md) for the setup, how the code works, and how to send a change. [DESIGN.md](https://github.com/shresthaoshan/airlock/blob/main/DESIGN.md) has the UI and lock rules.

## License

AirLock is released under the [MIT License](https://github.com/shresthaoshan/airlock/blob/main/LICENSE).
