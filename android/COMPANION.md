# VoltLink automotive companion (debug IoT experiment)

## Current status

At the user's request, **debug builds now register an Android Auto IoT service** for local
DHU testing. There is precedent: dashOBD's developer reported Google accepting its OBD app
under IoT in 2023 ([developer report](https://www.reddit.com/r/AndroidAuto/comments/16dwxnl/android_auto_obd_app_finally_released/),
[independent coverage](https://www.autoevolution.com/news/android-auto-obd2-app-now-available-for-download-220870.html)).
The earlier conclusion that telemetry categorically could not qualify was too strong.
This is a plausible experimental category, **not a guarantee of Play approval**.

`src/debug/.../CompanionCarService.kt` declares IoT through the debug manifest, requests
Car App API 7, and serves native `GridTemplate`s for Drive and Charging, plus a four-row
`PaneTemplate` for Vehicle. Drive has six tiles: battery (with connection status),
range, speed, signed battery power, trip consumption, and trip distance/time. Charging leads
with the same battery/status and range tiles as Drive, then charging power, ETA to 80%/elapsed
h:mm, and session energy/estimated cost (five tiles). Its charging-power tile uses the same
thick, needle-free dial; its battery tile reuses Drive's discrete battery level icon.
Drive battery icons use eight discrete Material resource levels
(0–7, full only at 100%); missing/invalid SOC shows a question-mark battery, not empty.
The Power and Speed tiles now run the custom-image experiment described below. Regen additionally requires
live speed ≥1 km/h; negative power without motion confirmation is labeled "Energy in",
not assumed to be braking. Active charging takes priority over regeneration.
It reuses the same presentation projection as the standalone
preview, with fixed labels/counts and at most 1 Hz
invalidation while visible. No custom surface or acquisition side effects; Drive Power/Speed
and Charging battery/power use experimental PNG indicators. Other images remain host-tinted vectors.
The service and permissive development host validator are absent from release builds.
The older experimental `car/` source remains unused by this service.

```bash
cd android
./gradlew assembleDebug
adb -s R5CWA0093XN install -r app/build/outputs/apk/debug/app-debug.apk
./scripts/car-emulator.sh -s R5CWA0093XN
```

In Android Auto developer settings, enable **Unknown sources** for the sideloaded debug app.
Restart the DHU session after installing. Open VoltLink from the launcher (and check the
phone's Android Auto → Customize launcher if it is hidden). Set up the adapter or explicitly
enable Demo mode on the phone while safely parked. Drive / Charging / Vehicle only read
shared state. The host owns colors, typography and row layout, in day and night themes.

Verified after this change: debug/test APK builds and JVM suite pass. The updated APK was
installed on phone `R5CWA0093XN`; all twelve `CompanionCarTemplateTest` cases pass there, checking
native pane/grid payloads, stable refresh titles, API 7 sizing fallback, API 8+ large sizing,
resource-only icons, battery levels/unknown state, draw/regen/charge/idle transitions,
host-default icon tint, compact readouts, custom-image bucket boundaries, cached resource
identity, speed/charging steps and unknown states, charging estimates/statuses, needle-free
thick arcs, pixel equality for all 64 packaged
frames and IoT-only discovery. Rendered frame contact sheets are saved locally at
`app/build/screenshots/companion/{power,speed,charging}-image-experiment.png`
(asset preview, not a DHU screenshot). DHU preset selection and SDK-preset fallback
were checked with stubbed SDK tools; the launcher script also passes `bash -n`.
The user confirmed DHU connectivity and liked the thicker needle-free Drive dials.
The Charging grid still needs DHU visual confirmation; Google Play approval is unverified.

Drive and Charging request large native grid tiles on hosts reporting Car App API 8+, opting into the
installed library's experimental sizing API. API 7 hosts retain the default grid size with
large resource images. The library version and minimum host API are unchanged. Grid icons
now use the host's default foreground tint (normally white/light gray in dark mode and dark
in light mode), not custom green: the user's host rendered the mint tint too dark. Battery,
power and speed images change only at telemetry state changes, with no continuous animation.
Vehicle has a separate car icon. Titles stay fixed while live values remain secondary text.
Power offers a compact numeric text variant if its state label won't fit; the sign and icon
still distinguish energy direction. Consumption puts `Avg kWh/100km` in the fixed label
and shows only the number below; trip time uses h:mm instead of h:mm:ss to reduce clipping.
The host still controls
columns, typography and scrolling; large sizing affects minimum tile width and image size,
not a custom font-size setting. The phone UI and acquisition remain unchanged.

### Dial image experiment (local debug only)

At the user's request, Power and Speed display custom images inside their existing grid tiles.
`src/debug/.../PowerImageExperiment.kt` supplies ten fixed frames per light/dark theme:
idle; three draw levels; three regen levels; charging; unconfirmed energy input; unknown.
Power's 20 transparent 192×192 PNGs are packaged under `src/debug/res/drawable-nodpi`
alongside 20 Speed images and 24 shared Charging images; resource-backed CarIcons are cached. Distinct resource
IDs matter: this library compares bitmap-backed icons by type, not by their pixels.
Using separate resource IDs prevents different states/themes comparing equal. No bitmap
allocation or drawing happens during template refreshes; the host loads/scales the resources.
The template never draws or animates a surface, and exact signed kW/state labels remain
host-rendered text below the image. Both dials use thicker 24px arcs (previously 13px) with
no needle or hub. The Charging dials use the same arc geometry and neutral theme palettes.
No phone screen changes.

`SpeedImageExperiment` uses a matching neutral arc: stopped, eight 20 km/h steps
(0–20, >20–40, …, >140 km/h, visually capped at 160), and a separate unknown state for
missing/invalid speed. These are coarse illustrations, not a speed limit or replacement for
the vehicle's speedometer. Exact uncapped km/h stays in native text; no new speed calculation.

`ChargingImageExperiment` keeps 12 frames per theme for charging power: unknown and levels
0–10, 20 kW steps rounded down, visually capped at 200 kW. Its SOC-step frames (10% steps
rounded down, full only at 100%, invalid SOC unknown) stay packaged for the experiment, but
the Charging battery tile now uses Drive's discrete level icon so both tabs read the same.
The 200 kW cap is illustrative, not a charger/vehicle limit. Exact uncapped kW and existing `≈` estimate
markers remain native text. Missing power is unknown, not zero or regen. Charging status,
ETA, elapsed session time, energy and estimated DKK cost reuse the existing projection.
No new charging detection, integration or calculations are introduced.

Draw bucket boundaries are 25 and 75 kW; regen magnitude boundaries are 10 and 30 kW.
These are **visual grouping thresholds**, not a vehicle-calibrated instrument scale or
percentage of available motor power. There are no numeric tick marks. Draw uses amber,
regen uses blue; state/position/text also communicate direction without relying on color.
Charging and unknown-motion energy input show a symbol instead of a magnitude arc.
Missing power shows a question mark, never a zero-power indication. Host theme changes are
checked even when telemetry stops changing, so cached images switch to the correct palette.

This intentionally explores custom-image rendering, not proof that dial-like imagery meets
Android Auto image-use/distraction rules. It remains debug-only and unapproved for release.
Host scaling and actual DHU/head-unit legibility need visual testing. The earlier vector-icon
selection remains in the source as the straightforward fallback if this is not useful.

### Larger DHU presentation

`scripts/car-emulator.sh` now defaults to the repository's
`scripts/dhu/voltlink_1080p.ini`: **1920×1080 at 240 dpi** instead of the SDK's 160-dpi
preset. This reduces the logical canvas from 1920×1080 dp to 1280×720 dp and makes the
whole host UI, including text, larger in the same pixel-sized window. This is a development
display setting, not control over a real car's screen density or a custom template layout.
Close and restart the DHU with the usual command to apply it:

```bash
./scripts/car-emulator.sh -s R5CWA0093XN
# Explicit original SDK preset for comparison:
./scripts/car-emulator.sh -s R5CWA0093XN -c default_1080p.ini
```

If an icon still appears as an old/wrong shape after installation, restart Android Auto
itself on the phone to rule out cached resources, then manually restart its head unit
server and reconnect. No app data or Android Auto settings need to be cleared.

The standalone preview below remains available, but is not the projected UI. The original
eligibility review below is retained as historical context; the debug IoT experiment
supersedes its claim that all DHU testing must be blocked.

## Eligibility review — 5 November 2026

**The standalone activity is not Android Auto; the debug IoT service is an unapproved experiment.**
The standalone debug activity is a layout/data prototype, not a host template emulator.

The official [supported categories](https://developer.android.com/training/cars) and
[quality rules](https://developer.android.com/docs/quality-guidelines/car-app-quality)
list media, communication, navigation, POI, IoT, weather and parked entertainment categories.
There is no OBD diagnostics or live vehicle telemetry category. VoltLink does not give
turn-by-turn directions, discover locations, control remote IoT devices, supply weather,
or provide media/communication/entertainment. Showing a charging session does not make an app
a charging-location POI app. IoT has OBD-app precedent, but approval for VoltLink still
requires Google review; a manifest declaration by itself does not establish eligibility.

The previous POI service registration and host-discovery metadata have been removed.
Existing experimental `car/` sources are retained, unregistered, to preserve in-progress
work; they are **not** the supported implementation or a publishing recommendation.
In particular their bitmap gauges, capacity/consumption fallbacks and dynamic titles
must not be used as evidence of a compliant or accurate Android Auto implementation.
The new companion does not call them.

## Repository analysis and shared data

- AGP 9, Kotlin, min SDK 29, target/compile SDK 36, Compose Material 3, coroutines,
  DataStore, SQLite; Car App Library 1.7.0 was already present. No dependencies added.
- `VoltLinkApplication` owns one `VehicleDataManager`, `TripTracker`, `ChargingTracker`
  and `HistoryStore` for the process. `BleObdConnection`/`MockObdAdapter` feed the existing
  poller, ISO-TP/profile decoders and `TelemetryReducer`.
- `companion/CompanionState.kt` projects existing states into nullable SI presentation
  values. It never connects, polls, starts trips, integrates energy, or writes history.
- `src/debug/.../CompanionPreviewActivity.kt` reads those shared StateFlows once per second
  while STARTED, independent of which tab is selected. A wall-clock tick expires data even
  when upstream stops emitting. Navigation never changes acquisition. Stop/destroy only
  stops UI observation, not the application-owned pipeline.
- Snapshot and timestamped signals expire after 15 seconds; connection loss hides live
  values immediately. Reconnection automatically reveals newly received signals. Profile
  support and the manager's received/live set gate metrics, including simulation.
- Temperature/SOH have no per-signal timestamps in the current domain model. They use
  the existing live set, command-miss invalidation and whole-stream timeout, not an invented
  timestamp. Add domain timestamps if strict per-signal expiry is needed for these metrics.
- Drive uses the existing trip average/distance/duration. Range is vehicle-reported when
  available, otherwise estimated only with fresh SOC, known profile capacity and an actual
  trip average. No WLTP/nominal-consumption fallback is fabricated.
- Charging uses tracker session energy/duration and `ChargingTimeEstimator` with fresh
  charge power, SOC and known capacity. Time-to-80 always targets 80, independent of the
  user's target. `≈` marks estimates (including SoC-slope power). Cost assumes the saved
  electricity tariff is **DKK/kWh**; there is no currency selector in the existing model.
  No tariff means unavailable, not free charging. No charger fees or conversion inferred.
- Complete means the tracker observed the configured target and charging has stopped,
  not proof of physical unplugging or a full battery. No plug-connection PID exists, so
  the UI does not claim physical cable state. Disconnected means the OBD link is lost.
- Vehicle lists received SOC, voltage, temperature, power and SOH, plus trip consumption
  and explicitly labeled profile capacity. There is no exposed odometer or measured
  available-capacity signal. Missing readings are omitted or shown as `—`, never zero-filled.
- Existing demo scenarios run through the same mock OBD/profile/reducer/trackers as the phone.
  Demo records are not persisted. Preview scenario buttons cannot replace an active real
  connection. Starting simulation is explicit and affects the shared phone demo session;
  disable it in phone Settings. Activity launch itself changes no acquisition settings.

## Run the standalone preview

Use an Android emulator for bench testing; do not run this on a driver's display.

```bash
cd android
./gradlew installDebug
adb shell am start -n com.simonkaring.voltlink/.companion.CompanionPreviewActivity
```

Select City / regen, Highway or DC charge to explicitly start the existing simulation.
Allow a full polling cycle (up to 30 seconds) for all decoded readings. Drive, Charging
and Vehicle share data; Day/Night overrides system theme for inspection. Connect a real
adapter from the unchanged phone UI if desired; the preview never opens a second link.
In Android Studio use an Activity run configuration targeting `CompanionPreviewActivity`.
The activity exists only in debug; release has no companion activity or car service registration.

For **emulator-only** resolution checks (do not change a personal device's display):

```bash
adb -s emulator-5554 shell wm size 800x480
adb -s emulator-5554 shell wm density 160
# Launch/relaunch the activity, inspect all three tabs in both themes.
adb -s emulator-5554 shell wm size 1280x720
# At the end:
adb -s emulator-5554 shell wm size reset
adb -s emulator-5554 shell wm density reset
```

The preview has system insets, scrolling for short screens/large text, large touch targets,
native focusable controls, and explicit labels for regen rather than color-only meaning.
It does not emulate host driving restrictions or certify rotary controller behavior.
Use keyboard Tab/arrows/Enter to check focus locally. Exercise disconnected → demo drive
→ regen → charge → drive; stop polling for 16 seconds to check stale state, then resume;
turn demo off to check disconnection. Unknown estimates must remain dashes.

```bash
./gradlew testDebugUnitTest
./gradlew assembleDebug assembleDebugAndroidTest
./gradlew connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=com.simonkaring.voltlink.companion.CompanionPreviewTest
./gradlew lintDebug
./gradlew testDebugUnitTest --tests '*KnowledgeBundleTest' -Pokf.export=true
```

## Android Auto / DHU boundary and future work

The [Car App Library](https://developer.android.com/training/cars/apps/library) does not
permit arbitrary Compose/WebView/CSS surfaces. A future eligible implementation should
consume `CompanionState` via `CarAppService` → `Session` → lifecycle-bound `Screen`.
Use host-rendered `PaneTemplate` (up to four rows), `ListTemplate` for details and, if the
host supports it, `TabTemplate` (Car App API 6+, with content IDs in API 7). Query host
content limits, use stable row titles/counts, and put changing values in secondary text.
Do not rasterize the proposed layout into template images or use a navigation surface
for gauges. The host controls type size, layout, palette and input; exact mint/large-number
styling in this standalone preview cannot be promised in templates.

[Refresh restrictions](https://developer.android.com/training/cars/apps/library/template-restrictions)
limit a task to five templates, with refresh/back/reset exceptions. `Screen.invalidate()`
requests another `onGetTemplate()`; it is not permission for arbitrary continuous redraw.
Coalesce updates (the proposed presentation cadence is at most 1 Hz), observe only while
visible, keep the content structurally stable, and respect host throttling. Collection and
trip tracking must continue independently. This is a future contract, not tested host code.

**DHU cannot run the standalone activity. It can discover the debug IoT service.**
Unknown-sources/developer mode permits local testing, not Play approval. Do not declare
POI/navigation to misrepresent the feature.

For a future eligible implementation, follow the official
[DHU guide](https://developer.android.com/training/cars/testing/dhu): install Android Auto
on a test phone and SDK Tools → Android Auto Desktop Head Unit Emulator. Connect with
`$ANDROID_HOME/extras/google/auto/desktop-head-unit --usb`, or enable Auto developer mode,
manually start its head unit server, run `adb forward tcp:5277 tcp:5277`, then the DHU.
Create a config containing `[general]`, `resolution = 800x480` (repeat with `1280x720`),
`dpi = 160`; start with `-c config.ini -i rotary` for rotary input. Exercise `day`, `night`,
`restrict all`, `restrict none`, `dpad rotate right`, `dpad click`, `dpad back` and navigation
back behavior. Capture with `screenshot filename.png`. The existing `scripts/car-emulator.sh`
is historical host tooling, not a way to launch this preview or a claim of eligibility.

Keep release registration disabled pending category review and real host validation.
Play approval and real head-unit safety validation remain unverified; a standalone
screenshot is not an Android Auto screenshot.

## Verification recorded locally

- Debug APK, instrumentation APK and R8 release build: successful.
- JVM suite: 146 cases, 0 failures/errors, 1 skipped (including 9 companion projection tests).
- Companion instrumentation: 2 tests passed at each of 800×480 and 1280×720 on an API 36
  emulator, covering disconnected navigation/theme switching and shared simulated charging
  → driving transitions. Existing phone `DemoDashboardSmokeTest`: passed.
- Actual running Compose screenshots (not generated mockups):
  `app/build/screenshots/companion/{800x480,1280x720}/` contains drive/charging in both themes,
  vehicle and disconnected captures. These are local ignored build artifacts.
  The instrumentation records originals inside the app's `files/companion-screenshots/`;
  retrieve with `adb exec-out run-as com.simonkaring.voltlink cat files/companion-screenshots/drive.png > drive.png`
  before Gradle's connected test task uninstalls the app.
- `lintDebug`: blocked by 3 errors in retained, pre-existing `car/VoltLinkScreen.kt`:
  experimental `GridTemplate.setItemSize`/`ITEM_SIZE_LARGE` use (line 480) and an invalid
  charging format string (line 545). No companion-source lint findings. These unrelated
  in-progress sources were not rewritten or suppressed.
- Confirmed merged release manifest contains neither the preview activity nor Auto host
  metadata/service. Emulator display overrides were reset after testing.
- Not validated: real adapter/head-unit operation, host restrictions, rotary hardware,
  Play approval, or the entire existing instrumentation suite. DHU cannot launch this
  unregistered standalone prototype.
