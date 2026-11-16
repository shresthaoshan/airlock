# Popup Settings Design

The menu bar icon opens a native AppKit popover. It closes on a second click or an outside click. Use native controls and no new dependencies.

Show Armed or Not armed, the live AirPods name and signal, an automatic lock checkbox, a threshold slider (-120 through -20 dBm, step 10), a weak signal delay field (0 through 30 whole seconds), the derived no-signal delay, and an Open at Login checkbox. Keep Open Log, Quit, and the immediate password warning.

Store settings in UserDefaults. Apply changes immediately and reset pending lock decisions. No-signal delay is always weak signal delay plus 3 seconds. Use -70 dBm and 5 seconds by default. Normalize old saved thresholds to the nearest slider step. Ignore old independent silence and arming overrides. Derive the arming threshold as weak threshold plus 4 dBm; keep the 5 second arming period and median window.

Live status requires recent accepted advertisements and powered-on Bluetooth. Keep the last target internally during signal loss so the silence rule can still lock. Refresh target information when the popup opens. Keep status updates active when automatic lock is disabled.

Alternatives: embedding controls in NSMenu is smaller but menu tracking complicates editing. SwiftUI hosting adds another state layer. Use NSPopover with AppKit controls to fit the existing application.

Validation: core setting normalization, saved values, weak and no-signal timing including 0 and 30 seconds, arming at the slider endpoints, and stale signal status. Run swift test and a release build. Inspect the popup in the running app if UI access permits it.
