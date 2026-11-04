# VoltLink Android — Kotlin & Jetpack Compose OBD-II App

Native Android companion to [VoltLink iOS](../ios/README.md). Same telemetry pipeline,
same vehicle profiles, same dark glass design language — implemented with Kotlin, Jetpack
Compose and the Android Bluetooth LE stack, with no shared build tooling with `ios/`.

- **Min SDK 29** (Android 10), **target/compile SDK 36**, Kotlin + Compose (Material 3).
- **BLE adapters**: Vgate iCar Pro 2S (18F0 / E781…), HM-10 (FFE0), generic UART (FFF0),
  Nordic UART, ISSC, plus a first-writable/notify fallback for clones.
- **Profiles**: Mercedes-Benz EQA 250 (29-bit UDS), EQA 250 OBDb community set, Volkswagen
  MEB, Hyundai/Kia E-GMP and Nissan Leaf (OVMS) hand-written decoders, 18 ABRP-backed
  community profiles read from `assets/abrp_pids/`, generic SAE J1979 OBD-II and generic EV.
- **Giving back**: the OBD terminal exports a community PID contribution JSON, and the trip log
  summarises the month (distance, net energy, efficiency, cost) from the saved electricity price.
- **Demo mode** with the same simulated driving/charging scenarios as the iOS app.
- **Exports, widget and shortcuts**: trip/charging CSV + GPX share sheets, a home-screen
  telemetry widget, launcher shortcuts for trip control and DTC scanning, and service
  reminders — the platform equivalents of the iOS share sheets, WidgetKit widget and
  App Intents.
- **Car, AI and sync**: an Android Auto / AAOS telemetry pane (CarPlay equivalent), an opt-in
  Gemini/OpenAI OBD log analyzer with a Keystore-encrypted key, an opt-in history mirror to a
  user-chosen folder (Drive, OneDrive, local), a 69-brand / 599-model vehicle catalog, and an
  Android 16 Live Update charging card.
- **Trip GPS**: a foreground location recorder fills the route samples while a trip records,
  which enables the GPX export; the permission is requested from the Start Trip action only.
- **Customizable UI**: dashboard widgets persist their metric, style, width and order, the
  car dashboard has its own persisted dial layout, and Settings lists which profile metrics are
  live. Charging sessions plot speed over time with a scrubbable readout.
- **Localized copy**: every user-visible string lives in `res/values/strings.xml` (253 keys),
  so a translation only needs another `values-<lang>` folder.

## Build & run

```bash
cd android

./gradlew assembleDebug                 # build the APK
./gradlew testDebugUnitTest             # engine unit tests (ISO-TP, profiles, telemetry, layouts)
./gradlew connectedDebugAndroidTest     # Compose UI tests (needs an emulator/device)
./gradlew lintDebug                     # Android lint
./gradlew assembleRelease               # R8 + resource shrinking (3.3 MB)

# Screenshot tests: dashboard, trips, charging, diagnostics (+ an expanded DTC),
# demo controls sheet, settings and HUD → app/build/screenshots
./gradlew recordScreenshots \
  -Pandroid.testInstrumentationRunnerArguments.class=com.simonkaring.voltlink.ScreenshotTest

# Widget and shortcuts are wired through the manifest:
#   .core.widget.TelemetryWidgetProvider  (Add widget from Settings)
#   .core.shortcuts.AppShortcuts          (long-press the launcher icon)
#   .car.VoltLinkCarAppService            (Android Auto / AAOS, charging category)
#   .services.TripLocationService         (foreground GPS while a trip records)
```

### Install on a phone

```bash
adb devices -l                          # find the serial; "unauthorized" means accept the prompt
./gradlew installDebug                  # phone is the only attached device

# Several devices (an emulator is running too): target one explicitly
adb -s R5CWA0093XN install -r app/build/outputs/apk/debug/app-debug.apk

# Runtime permissions can be granted up front, which skips the first-launch prompts:
adb shell pm grant com.simonkaring.voltlink android.permission.BLUETOOTH_SCAN
adb shell pm grant com.simonkaring.voltlink android.permission.BLUETOOTH_CONNECT
adb shell pm grant com.simonkaring.voltlink android.permission.ACCESS_FINE_LOCATION
adb shell pm grant com.simonkaring.voltlink android.permission.POST_NOTIFICATIONS
```

With more than one device attached, every Gradle task (and plain `adb`) needs the target. Export
it once instead of passing `-s` everywhere:

```bash
export ANDROID_SERIAL=R5CWA0093XN
./gradlew connectedDebugAndroidTest
```

`connectedDebugAndroidTest` uninstalls the app when it finishes, so reinstall it afterwards if you
want to keep using it. Demo mode is in memory only: after a reinstall, toggle **Settings → Demo /
Simulation mode** again for telemetry without an adapter.

### Install on the emulator

```bash
$ANDROID_HOME/emulator/emulator -avd VoltLinkPixel -gpu host -memory 4096 -cores 4
./gradlew installDebug

# The car pane needs an image with Android Auto on it (VoltLinkAuto34):
./scripts/car-emulator.sh               # boots that AVD and opens the Desktop Head Unit
```

### Android Auto on the Mac (Desktop Head Unit)

The Desktop Head Unit is Google's head unit simulator: it connects to a phone or emulator over
`adb forward` and renders the projected car screen in a window on the Mac, so the car pane can be
exercised without a car. It ships in the SDK extra **"Android Auto Desktop Head Unit Emulator"**:

```bash
sdkmanager "extras;google;auto"        # → $ANDROID_HOME/extras/google/auto/
```

`desktop-head-unit` lives in that directory next to the display configs in `config/`
(`default_1080p.ini`, `default_720p.ini`, `default_wide.ini`, `default_6in.ini`, `rotary.ini`, …).

**Emulator, one command:**

```bash
./scripts/car-emulator.sh                     # VoltLinkAuto34 + 1080p head unit
./scripts/car-emulator.sh -a MyAvd            # another AVD
./scripts/car-emulator.sh -c default_720p.ini # another head unit config
```

It boots the AVD when none is attached, turns on Android Auto developer mode and the head unit
server, forwards `tcp:5277`, and runs the DHU in the foreground. That terminal then takes the DHU
console commands: `help` lists them, `screenshot /tmp/car.png` saves the current head unit frame,
and `Ctrl-C` quits the DHU while the emulator keeps running.

**A real phone:** the phone has to serve the head unit connection itself.

```bash
# 1. Developer mode: Android Auto → Settings → About → tap "Version" 7×.
#    (The version row is inside About, not on the settings root.)
# 2. Start the server: Android Auto → Settings → ⋮ → "Start head unit server".
adb -s R5CWA0093XN shell 'cat /proc/net/tcp /proc/net/tcp6' | grep -c 149D   # 5277 = 0x149D

# 3. Forward the port, then open the head unit against it:
adb -s R5CWA0093XN forward tcp:5277 tcp:5277
cd "$ANDROID_HOME/extras/google/auto"
./desktop-head-unit -c config/default_1080p.ini -a 5277
```

Things that bite:

- Run the DHU from a real terminal. It reads its console from stdin and quits the moment that
  stream closes, so piping it (`| tee`) or launching it as a background job with a redirected stdin
  ends the session right after it connects.
- `-a 5277` connects through `adb forward`, which is what both the phone and the emulator need.
  `--usb` switches the DHU to libusb and expects a USB AOAP device, where it finds nothing.
- Keep the phone awake while projecting (`adb shell svc power stayon true`); a locked screen ends
  the session.
- In the head unit, open VoltLink from the app rail; the car pane then shows its telemetry and
  charging tabs.
- If the head unit server drops the session (`Failed to read from transport - disconnect`), force
  stop Android Auto and start the head unit server again before reconnecting.

`ScreenshotTest` records the dashboard, trip log, charging, diagnostics (including an expanded
fault-code entry after injecting the demo fault scenario), the demo control sheet, settings and
HUD screens as PNGs under `app/build/screenshots/` (the test copies them to
`/sdcard/Download/voltlink-screenshots` through the instrumentation shell so they survive the
post-test uninstall). The HUD capture is mirrored on both axes, exactly as it appears in the
windshield. The assertions cover a rendered, non-blank frame of the expected size rather than
a pixel baseline: exact pixels depend on device density, fonts and API level, so compare runs
across devices by eye.

`local.properties` points Gradle at the local SDK (`sdk.dir=…`). AGP 9 supplies Kotlin
support directly, so there is no `org.jetbrains.kotlin.android` plugin. `androidx.core` is
pinned to 1.18.0 because `NotificationCompat.ProgressStyle` and `setRequestPromotedOngoing`
(the Android 16 Live Update API) arrive there, while 1.19 would require AGP 9.1.

Release signing is injected, never committed: set `VOLTLINK_KEYSTORE`, `VOLTLINK_KEYSTORE_PASSWORD`,
`VOLTLINK_KEY_ALIAS` and `VOLTLINK_KEY_PASSWORD` (environment or `~/.gradle/gradle.properties`)
and `assembleRelease` produces a signed APK; without them it stays unsigned. CI runs
`.github/workflows/android.yml` (unit tests, lint, debug + test APKs, R8 release).

Runtime permissions: `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` on first launch (Android 12+),
`ACCESS_FINE_LOCATION` below that for scanning, `POST_NOTIFICATIONS` only when alerts are
enabled in Settings, and `ACCESS_FINE_LOCATION` for the trip route only when the user taps
Start Trip. Nothing requests location at launch.

## Feature parity with iOS

Implemented in this pass:

| Area | Notes |
| --- | --- |
| Live telemetry dashboard | Widget layout is user configurable (metric, dial/bar/number style, half/full width, order) and persisted; default is speed + power dials, SoC bar, 12 V and average consumption tiles, rolling chart |
| Profile metric status | Settings sheet listing every metric the active profile supports as Live, No data or Not connected, with the OBDb provenance notice |
| Car dashboard | Android Auto tabs for live telemetry and charging; each tab shows the first configured dial as a large hero gauge with the remaining metrics as rows beneath it. The dials (or the diagnostics badge) are chosen and ordered in Settings, capped at the six items every car host shows |
| Scrubbable charge chart | Charge power against elapsed time with a drag readout of time, speed and SoC, for live and recorded sessions |
| BLE ELM327 transport | Scan/connect/discover, command queue, 4 s timeout, stale-response drain, routing-failure recovery, OBD terminal log |
| ISO-TP / UDS decoding | Same multi-ECU bucket parser, 11- and 29-bit headers, plausibility bounds |
| Vehicle profiles | EQA 250, EQA OBDb community, VW MEB, Hyundai/Kia E-GMP, Nissan Leaf 62 kWh (OVMS), 18 ABRP-backed community profiles (Mach-E, Kona / Niro, e-Golf, e-Up!, Mini SE, Zoe ZE50/ZE40, ZS EV, I-Pace, Bolt, e:Ny1, U5, Atto 3, i3, S05), generic OBD-II, generic EV |
| ABRP PID import | `AbrpProfileLoader` reads `assets/abrp_pids/*.json`; equations are evaluated by a byte-math parser (`Signed()`, `{token:bit}`, `INT16(hi:lo)`, `<<n`, spreadsheet-column byte tokens) after ISO-TP reassembly, with per-ECU bucket pinning |
| Demo mode | City / highway / DC charging / fault injection, manual speed, throttle and regen overrides |
| HUD mode | Mirrored speed/power/SoC overlay |
| Diagnostics | Mode 03/07 scan across ECUs, curated + Wal33D definitions, Mode 02 freeze frames, Mode 04 clearing, severity detail |
| Persistence | SQLite (trips, trip samples, charging sessions, charging curves, battery health) |
| Trip log | Auto/manual recording, energy + distance integration, efficiency, SOC delta, recorded trace chart, and a this-month summary (distance, net energy, weighted efficiency, cost from the electricity price) |
| Charging | Live session, energy delivered, taper-aware time-to-target, session history with charge curve, battery-health trend |
| Units & settings | km/mi, °C/°F, kW/hp, charge target, electricity price per kWh, profile picker, adapter pairing |
| Alerts | Charging finished, charge target reached, fault codes, adapter loss, ongoing charging notification |
| Export | Trip CSV, charging CSV and trip GPX via `FileProvider` + the system share sheet (same headers and GPX layout as iOS), plus a community PID contribution JSON (`schemaVersion` 1, pretty-printed, sorted keys) built from the OBD terminal log |
| Home-screen widget | SoC, power, speed and charging state, refreshed from the live snapshot every 5 s; pin it from Settings |
| Launcher shortcuts | Start/stop trip, scan fault codes, open charging — the App Intents equivalent; the trip label tracks the recorder |
| Service reminder | Last vehicle-reported distance to service with 500/1000/2000/5000 km thresholds and a weekly alert |
| Vehicle catalog | `assets/vehicle_catalog.json` (69 brands, 599 models) browsed brand → model family → model year → variant, with an EV/All filter and one search field that matches brand, model, family or model year. The picked row selects its profile and remembers the model name for trips, the widget and reminders |
| Android Auto / AAOS | `CarAppService` + `TabTemplate` with telemetry and charging tabs; each tab is a `PaneTemplate` whose hero dial is the phone's `MetricDial` drawn into a bitmap, with rows for the other metrics refreshed from the same snapshot and charging session as the phone UI (paced to one push a second); discovered through the `com.google.android.gms.car.application` meta-data and `res/xml/automotive_app_desc.xml` (template capability) |
| AI log analyzer | Gemini (`AIza…`) or OpenAI (`sk-…`) decoding of the captured OBD trace; the key is AES-GCM encrypted under an Android Keystore key |
| Cloud backup | Opt-in mirror of trips, charging sessions and battery health to a folder picked with the system picker; restore merges the newest file by id and never deletes local rows |
| Live Update | Charging notification promoted (`setRequestPromotedOngoing`) with a `ProgressStyle` bar, target point and short critical SoC text on Android 16+ |
| Trip GPS | Foreground location service (`foregroundServiceType="location"`) during recordings, stale/imprecise fixes rejected, coordinates written into the trip samples |

Deliberate differences:

- Demo mode polls its own simulated PID set (generic J1979 + EQA BMS DIDs) so the dashboard
  shows power, SoC and speed even when the selected profile (e.g. EQA 250) publishes only
  pack voltage.
- Demo mode is switched on per session and never persisted; iOS keeps demo trips and charging
  sessions in memory, Android drops them when the recording ends so the history database only
  ever holds measured data.
- Trip distance is still integrated from telemetry speed rather than from GPS deltas; the
  location service only fills the route coordinates. Recording starts from the app (manual or
  auto trip), never from a background geofence.
- Rows that map to the generic OBD-II or generic EV profile (the “Vehicle Not Listed” entry)
  stay on the standard J1979 decoder and say so in the picker instead of pretending to decode
  pack data.
- An ABRP equation that is not arithmetic after substitution (e.g. `(A==6)||(A==8)`) yields no
  value, exactly like the iOS evaluator, so a definition relying on comparisons contributes
  nothing until the grammar grows.
- Cloud sync mirrors to a document-provider folder instead of iCloud: there is one file per
  backup, restore is newest-file-wins and merges by row id.
- The car pane renders the persisted row layout in order as a scrollable list, because a pane
  template silently stops at four rows and dropped the rest of the selection. The host still
  decides how many rows are visible at once, so later tiles need a scroll.
- The service reminder reads the `226504` service-distance metric, which only the EQA OBDb
  profile publishes; other profiles show the empty state.

## Knowledge bundle (OKF)

`knowledge/` is an Open Knowledge Format v0.2 bundle: plain markdown with YAML frontmatter that
records the vehicle profiles, telemetry metrics and curated DTCs for humans and AI agents. It is
the Android counterpart of `ios/knowledge/` and is generated from the same Kotlin types the app
runs, so it cannot silently describe stale behavior.

```bash
./gradlew testDebugUnitTest --tests '*KnowledgeBundleTest' -Pokf.export=true   # regenerate
./gradlew testDebugUnitTest                                                   # validate
```

- `knowledge/architecture/` is hand-authored; `vehicles/`, `telemetry/`, `diagnostics/` and the
  `index.md` files are generated by `KnowledgeBundle` in the unit-test source set. It installs an
  `AbrpProfileLoader` asset reader, so the generated pages list the real commands of the bundled
  ABRP profiles rather than a placeholder.
- Regenerate after changing `VehicleProfileId`, any profile's commands or `supportedMetrics`,
  `core/telemetry/TelemetryMetric.kt`, `assets/dtc_definitions.json`, or
  `assets/vehicle_catalog.json`.
- `testDebugUnitTest` fails when the checked-in bundle drifts from those sources. Never
  hand-edit generated concepts or an `index.md`; edit the Kotlin or the JSON and re-export.
- Add or edit `knowledge/architecture/*.md` directly — hand-authored concepts keep their own
  content and are indexed automatically by the next export.

## Architecture

```text
app/src/main/java/com/simonkaring/voltlink/
├── MainActivity.kt              # 5-tab Compose shell (Telemetry, Log, Charging, Diagnostics, Settings)
├── VoltLinkApplication.kt       # composition root + telemetry fan-out to trackers
├── core/
│   ├── bluetooth/BleConstants.kt      # GATT profiles per adapter family
│   ├── demo/                          # MockDrivingSimulation, MockObdAdapter, DemoProfile
│   ├── ai/                            # Gemini/OpenAI log analyzer + Keystore-backed key store
│   ├── backup/                        # portable history document, merge plan, SAF folder mirror
│   ├── notifications/                 # opt-in alerts + promoted (Live Update) charging card
│   ├── export/                        # Trip/charging CSV + GPX and the share-sheet bridge
│   ├── history/                       # TripHistoryInsights period arithmetic
│   ├── obd/                           # IsoTp parser, connection contract, DTCs, freeze frames
│   ├── shortcuts/                     # Launcher shortcuts + command intents
│   ├── telemetry/                     # TelemetryMetric, snapshot, plausibility, estimators
│   ├── vehicles/                      # VehicleProfile interface, hand-written + ABRP profiles
│   │                                  # (AbrpExpression/AbrpProfile), catalog, community
│   │                                  # PID contribution, reminders
│   └── widget/                        # Home-screen widget provider and snapshot store
├── car/                         # CarAppService, session and telemetry pane for Android Auto
├── data/                        # SQLite history store, DTC database, settings, reminder prefs
├── services/                    # BLE transport, polling loop, telemetry reducer/manager,
│                                # DTC scanner, trip tracker, charging tracker, trip GPS service
└── ui/                          # theme, gauges, dashboard, trips, charging, diagnostics, settings
```

The data flow is one-way and mirrors iOS: **BLE adapter → ISO-TP parser → vehicle profile →
`TelemetryReducer` → `VehicleDataManager` state → Compose / trackers**.

`TelemetryReducer` is a pure Kotlin state machine (no Android imports) so the decode and
charging-inference rules are unit-tested on the JVM:
`./gradlew testDebugUnitTest`.

## Attribution

- EQA OBDb signal definitions adapted from
  [OBDb/Mercedes-Benz-EQA](https://github.com/OBDb/Mercedes-Benz-EQA) (CC BY-SA 4.0),
  as adapted by the iOS app.
- VW MEB formulas and the bundled `assets/abrp_pids/*.json` documents adapted from
  [iternio/ev-obd-pids](https://github.com/iternio/ev-obd-pids).
- Vehicle catalog data from the OpenEV data dataset, as in the iOS app.
- DTC descriptions from [Wal33D/dtc-database](https://github.com/Wal33D/dtc-database) (MIT).
