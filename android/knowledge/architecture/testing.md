---
type: Architecture
title: "Testing and verification"
description: "Which Gradle commands to run, how to install on a phone or emulator and open the Android Auto head unit, what each suite covers, the screenshot harness, and the OKF drift gate for the Android bundle."
tags: [architecture, testing, okf]
status: stable
sources:
- id: readme
  resource: ../README.md
  title: Android README
- id: build
  resource: ../app/build.gradle.kts
  title: App module build script (screenshot and OKF wiring)
- id: agents
  resource: ../../AGENTS.md
  title: VoltLink agent guide
---

# Commands

Run from `android/`:

```bash
./gradlew assembleDebug                      # debug APK
./gradlew installDebug                       # install on the attached phone/emulator
./gradlew testDebugUnitTest                  # JVM tests, including the OKF drift gate
./gradlew connectedDebugAndroidTest          # instrumentation tests on every attached device
./gradlew recordScreenshots                  # run the screenshot tests and pull the PNGs
./gradlew assembleRelease                    # unsigned unless the VOLTLINK_* signing env vars are set
```

Run the unit tests after changing a PID decoder, the ISO-TP parser, metrics, or any of the
OKF source files. Instrumentation tests need a device; `recordScreenshots` writes
`app/build/screenshots/*.png`.

# Emulator

```bash
$ANDROID_HOME/emulator/emulator -avd VoltLinkPixel -gpu host -memory 4096 -cores 4
./gradlew installDebug
```

The car pane only shows up on an image with Android Auto installed (`VoltLinkAuto34` here).

# Phone

```bash
adb devices -l                           # serial; "unauthorized" means accept the prompt on the phone
./gradlew installDebug                   # works when the phone is the only attached device
adb -s R5CWA0093XN install -r app/build/outputs/apk/debug/app-debug.apk   # several devices attached
export ANDROID_SERIAL=R5CWA0093XN        # or target every Gradle and adb call this way

# Grant the runtime permissions up front to skip the first-launch prompts:
adb shell pm grant com.simonkaring.voltlink android.permission.BLUETOOTH_SCAN
adb shell pm grant com.simonkaring.voltlink android.permission.BLUETOOTH_CONNECT
adb shell pm grant com.simonkaring.voltlink android.permission.ACCESS_FINE_LOCATION
adb shell pm grant com.simonkaring.voltlink android.permission.POST_NOTIFICATIONS
```

`connectedDebugAndroidTest` uninstalls both APKs when it finishes, so a device that was just
verified loses the app: reinstall it, then re-enable **Settings → Demo / Simulation mode**, which
is in-memory only and therefore off after every reinstall.

# Desktop Head Unit

The Desktop Head Unit (DHU) is Google's head unit simulator. It reaches the phone or emulator
through `adb forward tcp:5277`, renders the projected car screen on the Mac, and takes console
commands from its own terminal: `help`, `screenshot /tmp/car.png` to save a frame, `Ctrl-C` to
quit. Install it with `sdkmanager "extras;google;auto"`; the binary and its display configs
(`default_1080p.ini`, `default_720p.ini`, `default_wide.ini`, `rotary.ini`, …) land in
`$ANDROID_HOME/extras/google/auto/`.

## Emulator, one command

```bash
./scripts/car-emulator.sh                     # VoltLinkAuto34 + 1080p head unit
./scripts/car-emulator.sh -a MyAvd            # another AVD
./scripts/car-emulator.sh -c default_720p.ini # another head unit config
```

The script boots the AVD when none is attached, enables Android Auto developer mode and the head
unit server, forwards `tcp:5277`, and runs `desktop-head-unit` in the foreground.

## Real phone

The phone has to serve the connection itself:

```bash
# Developer mode: Android Auto → Settings → About → tap "Version" 7x (the row is inside About).
# Start the server: Android Auto → Settings → ⋮ → "Start head unit server".
adb -s R5CWA0093XN shell 'cat /proc/net/tcp /proc/net/tcp6' | grep -c 149D   # 5277 = 0x149D
adb -s R5CWA0093XN forward tcp:5277 tcp:5277
cd "$ANDROID_HOME/extras/google/auto" && ./desktop-head-unit -c config/default_1080p.ini -a 5277
```

- Run the DHU in a real terminal: it quits as soon as its stdin stream closes, so piping it
  (`| tee`) or starting it as a background job ends the session right after it connects.
- `-a 5277` goes through `adb forward`. `--usb` switches to libusb and needs a USB AOAP device,
  where an emulator always comes up empty.
- Keep the phone awake (`adb shell svc power stayon true`); a locked screen drops the session.
- Open VoltLink from the head unit's app rail to see the car pane.

# Suites

| Location | Covers |
| --- | --- |
| `app/src/test/.../core/obd` | ISO-TP reassembly and ELM framing |
| `app/src/test/.../core/vehicles` | Profile decoders, ABRP parsing, catalog search matching |
| `app/src/test/.../core/telemetry` | Metric semantics, charging estimates, session average power |
| `app/src/test/.../services` | Trip location start-command policy, fix filtering, reducer state machine |
| `app/src/test/.../core/{ai,backup,export,history}` | Log analysis, backup merge, GPX/CSV export, monthly insights |
| `app/src/test/.../okf` | OKF conformance and drift for `android/knowledge` |
| `app/src/androidTest/.../ScreenshotTest` | Captures every screen (dashboard, trips, charging, diagnostics, DTC detail, demo sheet, settings, HUD) |
| `app/src/androidTest/.../ui` | Sheet and picker flows driven through the real activity |
| `app/src/androidTest/.../DemoDashboardSmokeTest` | Boots disconnected, switches demo on, checks the tab shell |
| `app/src/androidTest/.../DemoModeLifecycleTest` | Demo off/on resumes polling; simulated trips and charging sessions stay out of history |

# Font-scale resilience

Phones often run a system font scale above 1.0 (1.15 is common) and a higher density than an
emulator, which leaves text roughly a quarter less room per row. Reproduce that before
declaring a layout done:

```bash
adb shell wm density 450
adb shell settings put system font_scale 1.15
# ... capture, then restore
adb shell wm density reset
adb shell settings put system font_scale 1.0
```

Layouts must honour the user's scale — never clamp `sp` — but nav labels stay single-line and
sheets scroll.

# OKF bundle

`android/knowledge` is an Open Knowledge Format v0.2 bundle, the Android counterpart of
`ios/knowledge`. `knowledge/architecture/` is hand-authored; `vehicles/`, `telemetry/` and
`diagnostics/` plus every `index.md` are generated by `KnowledgeBundle` (in the unit-test source
set, so it reads the live profiles through `AbrpProfileLoader.install`).

```bash
./gradlew testDebugUnitTest --tests '*KnowledgeBundleTest' \
  -Pokf.export=true                          # regenerate android/knowledge
./gradlew testDebugUnitTest                  # validate (fails on drift)
```

Regenerate after changing `VehicleProfileId`, any profile's commands or `supportedMetrics`,
`core/telemetry/TelemetryMetric.kt`, `assets/dtc_definitions.json`, or
`assets/vehicle_catalog.json`. Never hand-edit generated concepts or an `index.md`; edit the
Kotlin or the JSON and re-export.

The iOS bundle is separate and is regenerated from `ios/` with
`swift run VoltLinkCLI okf export` (validated by `swift test`).

# Verification gates

There is no hosted CI, so these run locally and belong in the change description:
`./gradlew testDebugUnitTest` (includes the OKF check), the instrumentation suite on a device,
and — for UI work — a fresh `recordScreenshots` inspected at the default *and* a raised font
scale.

Related: [Android app structure](/architecture/overview.md), [Vehicle profiles](/architecture/vehicle-profiles.md).
