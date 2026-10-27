# Volta

A native macOS menu bar battery utility, written in Swift with SwiftUI (plus AppKit where needed).

- **macOS 15 Sequoia or later**, Apple Silicon and Intel
- Menu bar only (`LSUIElement = YES`), popover built with `MenuBarExtra(.window)`
- Event-driven: reacts to IOKit power-source notifications; measured idle CPU ≈ 0.03 %
- Distributed outside the Mac App Store (Developer ID + notarization). **App Sandbox is off** on purpose: SMC access, `top`, `system_profiler`, and the privileged helper aren't possible in the sandbox.

## Features

| Area | What it does |
|---|---|
| Battery data | Percentage, charging/AC state, time to empty/full (IOPowerSources); cycles, raw/design capacity, health, temperature, voltage, amperage, watts, charger wattage (AppleSmartBattery + SMC). Desktops show "No internal battery". |
| Menu bar icon | Battery icon rendered with `ImageRenderer`. Fully customizable in Settings › Icon: color mode (monochrome template / colored / text only), shape (rounded, pill, outline), percentage placement (inside, beside, hidden), size, charging bolt, and custom high/medium/low/charging colors with adjustable thresholds. Re-rendered only when something visible changes. |
| Effects | Settings › Effects: glow colors (low and charged), brightness, thickness, speed, and pulse count; banner position (top center, top right, bottom right) and duration; global mute and master volume. Every section has a Preview button. |
| Alerts | Unlimited rules: "drops to X %" / "reaches X %", system or custom sound with volume, pill banner and/or screen glow, once or repeat every N minutes. Fires once per crossing and re-arms after moving back past the threshold. Optional Focus awareness and macOS notifications. |
| History | SwiftData: level every 10 min (kept 7 days) and a daily health snapshot (kept forever). Swift Charts for level/24 h, health and cycles over months. CSV export. |
| Energy | Per-app Energy Impact from `top`, helpers grouped under their app, sampled only while the tab is visible. |
| Charging | Charge limit (50–100 %), "Charge to 100 % once", and sailing mode through a root helper (`SMAppService.daemon` + XPC). |
| Devices | Magic Mouse/Keyboard/Trackpad via IORegistry, AirPods and other Bluetooth devices via `system_profiler` (every 5 min), with optional low-battery alerts. |

## Project layout

```
Volta/
├── App/        VoltaApp (entry point, scenes), AppModel (service wiring)
├── Models/     BatteryInfo, AlertRule, ConnectedDevice, HistoryModels (SwiftData), AppSettings
├── Services/   BatteryService, PowerSourceReader, SmartBatteryReader, AlertEngine,
│               BannerPresenter, GlowPresenter, SoundPlayer, NotificationSender,
│               HistoryService, EnergyService, DeviceService, ChargeController,
│               MenuBarIconRenderer, LaunchAtLogin
│   └── SMC/    SMC.swift (AppleSMC client), Volta-Bridging-Header.h (C structs)
├── Views/      PopoverView, OverviewView, HealthView, EnergyView, BatteryIconView
│   └── Settings/  General, Alerts, Charging, Devices, About
└── Helper/     HelperDaemon, HelperProtocol (XPC + key detection), bashirul.Volta.helper.plist
```

The architecture is MVVM: services are `@Observable` and own all state; views only read from them. `AppModel` connects `BatteryService` change events to the alert engine, history, and charge controller.

## Building

1. Open `liloTect.xcodeproj` in Xcode and select the **Volta** scheme → **My Mac**.
2. Build and run (⌘R). The battery icon appears in the menu bar; there is no Dock icon.

Everything except charge limiting works with the default "Sign to Run Locally" signing.

### Embedding the helper (one-time Xcode setup)

`SMAppService.daemon(plistName:)` only looks in `Volta.app/Contents/Library/LaunchDaemons/`. The project uses a synchronized folder, which copies plists to `Contents/Resources/`, so add one build phase by hand:

1. Select the **Volta** target → **Build Phases** → **+** → **New Copy Files Phase**.
2. **Destination:** *Wrapper*, **Subpath:** `Contents/Library/LaunchDaemons`.
3. Add `Volta/Helper/bashirul.Volta.helper.plist`, with "Code Sign On Copy" unchecked.
4. Optional: in the file inspector, remove the plist from the target's Copy Bundle Resources so it isn't also copied to Resources.

The helper is the main `Volta` executable itself, launched by launchd with `--helper` (see `BundleProgram` and `ProgramArguments` in the plist), so there is no second binary to build. Settings › Charging shows a warning if the plist isn't embedded.

## Signing and notarization

1. **Team:** Volta target → Signing & Capabilities → choose your team. Keep **Hardened Runtime** on (already set) and the **App Sandbox** off.
2. **Focus awareness (optional):** add the *Communication Notifications* capability. Without it `INFocusStatusCenter` never reports a Focus, and alerts behave normally.
3. **Archive and export with Developer ID:**

   ```sh
   xcodebuild -project liloTect.xcodeproj -scheme Volta -configuration Release \
     -destination 'generic/platform=macOS' -archivePath build/Volta.xcarchive archive

   # ExportOptions.plist: method = developer-id, teamID = YOURTEAMID
   xcodebuild -exportArchive -archivePath build/Volta.xcarchive \
     -exportOptionsPlist ExportOptions.plist -exportPath build/export
   ```

   With the generic destination the Release build is universal (arm64 + x86_64). Without `-destination`, xcodebuild builds only for the current Mac. Check with `lipo -archs build/export/Volta.app/Contents/MacOS/Volta`.

4. **Notarize and staple:**

   ```sh
   ditto -c -k --keepParent build/export/Volta.app build/Volta.zip
   xcrun notarytool store-credentials volta-notary --apple-id you@example.com --team-id YOURTEAMID
   xcrun notarytool submit build/Volta.zip --keychain-profile volta-notary --wait
   xcrun stapler staple build/export/Volta.app
   spctl -a -vv build/export/Volta.app   # should say "Notarized Developer ID"
   ```

5. Distribute the stapled app in a DMG or ZIP. The helper must stay inside the signed bundle; never copy it to `/Library/LaunchDaemons` yourself.

The helper only accepts XPC connections from a process with bundle ID `bashirul.Volta` signed by the same Team ID (`NSXPCConnection.setCodeSigningRequirement`). The app checks the helper the same way.

## Charge limiting: how it works and its limits

> ⚠️ This writes undocumented SMC keys. It may stop working after a macOS or firmware update.

- Detection reads keys, which needs no privileges, and only ever uses these known sets:
  - **Intel:** `BCLM` (ui8 charge ceiling, enforced by firmware).
  - **Apple Silicon, newer firmware:** `CHTE` (4 bytes; `01 00 00 00` stops charging, `00 00 00 00` resumes).
  - **Apple Silicon, older firmware:** `CH0B` + `CH0C` (1 byte each; `02` stops charging, `00` resumes).
- On Apple Silicon, Volta toggles charging around the limit with a 2 % band, driven by IOKit battery events.
- Normal charging is restored when:
  - the app quits (`applicationWillTerminate`)
  - the XPC connection drops (crash or force-quit)
  - the Mac boots (the daemon has `RunAtLoad`)
  - you choose **Remove Helper…**, which restores charging and then unregisters the daemon
- Deleting Volta.app removes its `SMAppService` registration.
- **Tested hardware:** on the MacBook Air (M5) running macOS 27 used for development, *none* of the known keys exist. Only `CHIE` and other undocumented `CH*` keys are present. Volta reports "Not supported on this firmware" there and writes nothing. The open-source [`battery`](https://github.com/actuallymentor/battery) project tracks new key names as Apple changes them; add a new case to `ChargeControlMethod` once a key set is confirmed.
- **One instance at a time:** launching Volta again (or running a new build) makes the older copy quit, so only one icon ever appears. Xcode Preview hosts never add a menu bar icon.
- **Two battery icons?** macOS shows its own battery icon too. Turn it off in System Settings › Control Center › Battery › "Show in Menu Bar". Settings › General has a shortcut.

## Notes

- **Health figure:** Volta shows raw `AppleRawMaxCapacity ÷ DesignCapacity`. On newer firmware this comes from `BatteryData.NominalChargeCapacity`. macOS smooths its own "Maximum Capacity" value over time, so the two can differ by a few percent. A new battery can read above 100 %.
- **Temperature:** read from AppleSmartBattery when it's published. Otherwise it comes from the SMC battery thermistors (`TB0T`/`TB1T`), which is the case on M5 / macOS 27.
- **Polling:** temperature and health refresh every 60 s only while the popover is open. Energy sampling runs only while the Energy tab is visible. History logging and Bluetooth device refresh use 10-minute and 5-minute timers with generous tolerance.
- **Updates:** the About tab has a placeholder "Check for Updates…" button. To enable it, add [Sparkle](https://sparkle-project.org) through Swift Package Manager and call `SPUStandardUpdaterController.checkForUpdates(_:)`.
- **iPhone / iPad battery:** there is no reliable public API, so it isn't shown.
