# Experimental iPhone Mode

Add a source selector to the existing popup: AirPods or iPhone (experimental). Only the selected source controls locking. Keep AirPods as the default. Save separate thresholds and delays for each source. iPhone defaults are -60 dBm and 10 seconds; no-signal delay remains the configured delay plus 3 seconds.

Discover nearby named Apple Bluetooth LE devices, excluding AirPods pairing advertisements. Let the user select the iPhone explicitly. Save its CoreBluetooth identifier and display name. Follow only that identifier. Never select a replacement by name or signal strength. An unselected phone cannot arm or refresh the silence timer. Show the saved phone even when absent, and show a clear selection prompt when none is selected.

Reuse Decider and the existing 5-second median and arming period. The iPhone has no ear-status condition. Switching source, phone, or settings resets pending decisions and live status. Continue passive discovery while automatic lock is disabled. AirPods target refresh must not reset an active iPhone decision.

Use the existing CoreBluetooth scanner, native AppKit controls, and UserDefaults. No iPhone app, pairing requests, active connections, or new dependencies. Update Bluetooth permission text. Label the feature experimental because sleep/wake, app restart, and longer identifier stability are not yet validated.

Feasibility evidence: the candidate disappeared when iPhone Bluetooth was off and returned with the same identifier when on. A stationary 180-second scan recorded 167 packets, median -38 dBm, range -49 to -36 dBm, and a largest gap of approximately 7 seconds. A live diagnostic using -60 dBm and 10 seconds armed, produced one would-lock event when away, and armed again on return. No diagnostic locked the screen.
