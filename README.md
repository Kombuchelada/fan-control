<img src="assets/icon.png" width="96" height="96" alt="">

# Fan Control

A native macOS menu bar app for choosing how your MacBook's fans respond to heat.

Pick a fan curve from the menu bar:

| Curve | Behavior |
| --- | --- |
| **Automatic** | macOS manages the fans, as it does without this app. |
| **Quiet** | Minimum speed until 62 °C, then an unhurried ramp. Brief load spikes go unheard. |
| **Balanced** | A gentle ramp from 52 °C, with smoothing so the fans don't hunt up and down. |
| **Performance** | Ramps early and fast to keep the CPU cool enough to hold boost clocks. |
| **Full Speed** | Every fan at its maximum. |

Curves are defined as a fraction of each fan's own min–max range, against the hotter of the CPU and GPU die temperatures. Each curve also sets how quickly the fans respond: temperature smoothing, hysteresis (how far temperatures must fall before fans slow), and rate limits for speeding up and slowing down. See `Sources/FanKit/FanProfile.swift`.

The menu shows live CPU and graphics temperatures and each fan's speed. **Settings…** (⌘,) adds a chart of the curves with the current temperature marked, plus options to show the temperature in the menu bar and open at login.

## Safety

- Above 90 °C every curve ramps toward full speed, reaching it at 97 °C, whatever the chosen curve says.
- Fans go back to automatic control when the app quits or crashes, when the helper is stopped, and at boot.
- If no temperature can be read, the helper runs the fans at full speed.
- Target speeds are always clamped to each fan's own SMC limits.

## How it works

- **`FanControl`**: the menu bar app (AppKit `NSStatusItem` and `NSMenu`; a SwiftUI and Swift Charts Settings window). It reads sensors from the SMC directly, which needs no privileges.
- **`FanControlHelper`**: a small root LaunchDaemon (`app.fancontrol.helper`). Writing fan speeds to the SMC requires root, so the helper runs the control loop once a second and accepts XPC connections only from a client signed as `app.fancontrol.FanControl`. The app installs it the first time you choose a curve, using the standard macOS administrator prompt. You can remove it from Settings.
- **`FanKit`**: shared code: SMC access, sensors, curves and the curve controller.
- **`fanctl`**: a diagnostic command line tool: `fanctl status`, `fanctl keys [prefix]`, `sudo fanctl set <fan> <rpm>`, `sudo fanctl auto`.

Built and tested on a MacBookPro16,1 (16-inch, 2019, Intel) running macOS 26. The SMC keys used (`FNum`, `F<n>Ac/Mn/Mx/Tg/Md`, `TCXC`, `TGDD`, …) are those of Intel Macs. Apple silicon Macs use a different fan-control scheme, which this app doesn't support.

Don't run this alongside another fan-control app (such as Macs Fan Control) that is also controlling the fans. The two will fight over them.

## Building

Requires only the Xcode Command Line Tools.

```sh
scripts/build.sh            # → build/Fan Control.app (ad-hoc signed)
scripts/build.sh --install  # also copy to /Applications and launch
scripts/test.sh             # unit tests for curves and the controller
swift scripts/make-icon.swift   # regenerate Resources/AppIcon.icns
```

Debug builds can render their own menu and Settings window to PNGs for layout checks: `FANCONTROL_SNAPSHOT=/some/dir .build/debug/FanControl` (run inside an app bundle).

If you change the helper, bump `HelperConstants.helperVersion` so the app reinstalls it.

## Uninstalling

Open **Settings… → Fan control helper → Uninstall…**, then delete the app. Or remove the helper manually:

```sh
sudo launchctl bootout system/app.fancontrol.helper
sudo rm /Library/PrivilegedHelperTools/app.fancontrol.helper /Library/LaunchDaemons/app.fancontrol.helper.plist
```
