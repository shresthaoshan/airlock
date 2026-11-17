# AirLock design

The rules for what AirLock shows and how it decides to lock: the menu-bar icon, the menu, the lock rules and the Bluetooth scan.
When the code and this file disagree, the code is correct. Update this file.

## Principles

- **One job.** AirLock locks the Mac when you walk away. It has no other features.
- **A false lock is better than no lock, but both are bugs.** Each lock writes its reason to the log, so a user can tune the settings.
- **Listen only.** AirLock reads Bluetooth LE advertisements. It never connects, pairs or sends.
- **Native first.** Use AppKit controls and SF Symbols. No custom look.

## Menu-bar icon

| Symbol | State |
|---|---|
| `lock.fill` | Armed |
| `lock.open` | On, not armed |
| `lock.slash` | **Lock When I Walk Away** is off |

A click opens the menu. The tooltip is "AirLock".

## Menu

The status item has an `NSMenu` with one item. The item's view is `PopupViewController.view`, 336 pt wide.

- A menu, not an `NSPopover`: menu tracking keeps the menu bar visible over full-screen apps.
- Use only controls that work inside menu tracking: buttons, checkboxes, radio buttons, segmented controls, sliders and text fields. An `NSPopUpButton` cannot open its menu inside the status menu.
- Before the menu opens, AirLock updates the controls, refreshes the AirPods target and checks the password setting.
- To show an alert or System Settings, call `menu.cancelTracking()` first.

Controls, from top to bottom:

| Control | Behavior |
|---|---|
| Title "AirLock" | 17 pt, semibold |
| **Lock device** | Segmented control: "AirPods", "iPhone". The iPhone note marks iPhone mode as experimental. The short labels keep the row inside 336 pt on every macOS font setup |
| iPhone list | iPhone mode only. One radio button for each nearby named Apple device, and for the saved iPhone when it is absent. Same names get an ID suffix (" · 1A2B3C"). Empty: "No iPhones nearby." |
| iPhone note | iPhone mode only. "Experimental. Select your iPhone from nearby Apple devices. If it stops being detected, select it again." |
| State | "Armed" in green, or "Not armed" in the secondary color |
| Device | "Name · −55 dBm". Without a live signal: "No live AirPods", "Select an iPhone to start." or "No live iPhone signal" |
| **Lock When I Walk Away** | Checkbox. Saved in `UserDefaults` (`enabled`) |
| Weak signal threshold | Slider, −120 to −20 dBm, 11 tick marks, tick values only |
| Weak signal delay | Text field, whole seconds 0 to 30. Invalid input shows "Enter a whole number from 0 to 30." in red and changes nothing |
| No-signal delay | "No-signal delay: N s" (delay + 3) |
| **Open at Login** | Checkbox. `SMAppService.mainApp`. "Approve AirLock in Login Items." shows when approval is necessary |
| Password warning | Shows when `sysadminctl -screenLock status` does not report "immediate" |
| **Open Log**, **Quit AirLock** | Buttons |

The view height follows its content. A signal update must not change the height.

## Lock rules

`Decider` makes all decisions. Times are seconds on `ProcessInfo.systemUptime`.

| Rule | Value |
|---|---|
| Median window | 5 s of readings |
| Arm | Median ≥ threshold + 2 dB for 5 s |
| Weak signal lock | Armed, and median < threshold for the delay |
| No-signal lock | Armed, and no reading for the delay + 3 s |
| After a lock | Not armed. Arms again only by the arm rule |
| AirPods out of ears | Disarms. Status bits `0x0A` are both clear |

Rules:

- The arm level must stay above the lock level. Without the gap, a signal at the threshold arms and locks again and again.
- Changing the device, the iPhone or a setting resets the decisions and the live signal.
- A lock runs `pmset displaysleepnow`.
- The tick timer (1 s) and the target timer (60 s) run in `.common` run loop modes, so the rules keep running while the menu is open.

## Settings

Each device has its own threshold and delay in `UserDefaults`.

| Device | Threshold key | Delay key | Defaults |
|---|---|---|---|
| AirPods | `weakRSSI` | `weakSeconds` | −60 dBm, 5 s |
| iPhone | `iphoneWeakRSSI` | `iphoneWeakSeconds` | −60 dBm, 10 s |

Saved thresholds round to the nearest 10 dBm. Other keys: `lockDevice`, `iphoneIdentifier`, `iphoneName`, `enabled`.

## Bluetooth

- One `CBCentralManager` scan on the main queue, no service filter, duplicates allowed.
- Readings of 0 dBm or more, or −127 dBm or less, are ignored.
- **AirPods:** System Information (`system_profiler SPBluetoothDataType -json`) gives the connected Apple headphones: name, product ID and battery. An advertisement matches when it is type `0x07`, has the same product ID, and the battery levels are within 10% in either bud order. `PeerPicker` follows one matching peer and changes to a new one after 5 s of silence, because the address rotates.
- **iPhone:** Named Apple advertisements that are not type `0x07` are candidates. Names with "AirPods" or "Beats", and the connected headphones, are not. AirLock follows only the saved CoreBluetooth identifier.
- A candidate leaves the list 30 s after its last advertisement.

## Log

`~/Library/Logs/AirLock.log`, one line per event: start, Bluetooth state, target, armed, disarmed with reason, `LOCK:` with reason, settings changes, and the median every 10 s.
