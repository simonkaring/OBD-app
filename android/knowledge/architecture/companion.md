---
type: Architecture
title: "Automotive companion preview"
description: "Read-only telemetry projection, standalone preview, and experimental debug Android Auto IoT service."
---

# Platform boundary

Debug builds register `CompanionCarService` under IoT for local Android Auto/DHU testing,
following reported OBD-app precedent (dashOBD). This does not guarantee Play approval.
Release remains unregistered. The old experimental `car` source is retained unused.
See `android/COMPANION.md` for category evidence, launch commands and the test matrix.

The debug service creates a Session and lifecycle-bound Screen with three native tabs
(Car App API 7): Drive uses six GridTemplate tiles (battery/status, range,
speed, signed power, consumption, trip/time); Charging uses six grid tiles, leading with the
same battery/status and range tiles as Drive, then charge power, ETA to 80%, the elapsed
session clock and energy/estimated DKK cost; Vehicle retains a four-row
PaneTemplate. Stable item/row titles carry changing values in secondary text. Drive Power/Speed
and Charging power run the debug-only image experiment below; the Charging battery tile reuses
Drive's discrete battery level icon and every other icon is a vector.
The host controls layout/size.
API 8+ hosts receive an experimental large-item sizing request; API 7 retains default
grid sizing. Resource icons request the large image slot and use the host's default
foreground tint for contrast instead of custom green. SOC selects one of eight discrete
Material battery levels, with a distinct unknown icon; power changes between draw, regen,
charging, idle and unavailable states. Regen requires known motion and is never inferred
during active charging. No continuous animation is used. Titles/counts
remain fixed while icons and secondary text change. Grid titles are single short words
(`Battery`, `Range`, `Speed`, `Power`, `kWh/100 km`, `Trip`, `Charge`, `To 80%`, `Energy`),
because the library accepts only a plain title string with no short variant and the host
ellipsizes longer labels on narrow tiles; qualifiers, `≈`, the h:mm clocks and DKK cost stay in
the value line. The h:mm trip clock also reduces clipping. The repository DHU preset now
uses 1920×1080 at 240 dpi to enlarge host text/controls; it does not change real head units.
It reads the same projection at most once per second while STARTED,
calling invalidate only on state or host-theme change. No extra acquisition. The permissive
DHU host validator and service exist only in debug.

## Dial image experiment

`PowerImageExperiment` selects ten coarse frames per theme: three draw levels (boundaries
25/75 kW), three regen levels (10/30 kW magnitude), idle, charging, unconfirmed energy input
and unknown. These thresholds are visual grouping, not calibrated motor limits. Android
Canvas is only a reference asset generator in instrumentation: the 64 transparent 192px
PNGs are packaged in debug resources and their resource-backed CarIcons are cached.
Distinct resource IDs avoid the library's bitmap-icon equality limitation. Power and Speed
use thick 24px arcs with no needles. A small 75%-alpha hub glyph names the quantity - gauge for
speed, up/down trend arrow (pause when idle) for power direction, bolt for charging - so the
three dial families are distinguishable without reading the text. The charging dial paints its arc
and bolt in `Theme.regenGreen` only while power flows; zero or absent charging power selects the
separate `idle` frame (empty dial, neutral grey bolt) instead of the unknown question mark, so an
idle session is neither green nor an error. `SpeedImageExperiment` has stopped, eight
20 km/h steps (rounded up, visually capped at 160), and missing/invalid-speed frames per
theme. The coarse illustration is not a speed limit; exact uncapped speed stays in native
text. Charging keeps its 24 neutral images (unknown and levels 0–10 per theme) for the power tile:
20 kW steps rounded down and visually capped at 200 kW, not a vehicle charging limit. The
charging battery tile now uses Drive's discrete level icons instead of the SOC-step images,
which stay packaged for the experiment. Exact uncapped
charge power and existing estimate markers remain text. Both use the same needle-free arc
renderer as Speed during asset generation. No charging detection or telemetry calculation
changes. There is no runtime drawing, animation, live
custom surface, redraw loop, new dependency or acquisition change. Exact values and labels
remain host-rendered secondary text; unknown values show symbols, not zero arcs. Drive's
Power charging state remains a charging symbol, never a regen magnitude arc.
The screen's 1 Hz observer also notices theme changes without requiring fresh telemetry.
This is a local debug rendering experiment, not a claim of Play approval or compliance for
dial-like images. Actual host sizing/readability remain a manual check.

# Data flow

The existing `VoltLinkApplication` remains the sole owner of `VehicleDataManager`, BLE/mock
connections, polling, trip/charging trackers and SQLite persistence. `companionState` is a
pure read-only projection of those snapshots and tracker states. Unsupported/missing/stale
readings remain unavailable. Capacity is a profile specification, not a measured signal;
range requires a real trip average or a reported range. Charging ETA reuses the domain
estimator and cost uses the existing tariff interpreted as DKK/kWh.

`CompanionPreviewActivity` exists only in debug and reads shared StateFlows once per second
while STARTED. A wall clock expires silent telemetry after 15 seconds. Navigation does not
start/stop acquisition. Explicit scenario buttons use the existing simulation, cannot replace
an active real connection, and do not persist demo history. The phone UI is unchanged.
Temperature/SOH rely on existing live-metric invalidation because their domain values lack
individual timestamps. The standalone Compose display is not sent to a Car App Library host.

# Verification

`CompanionStateTest` covers stale/disconnected/unsupported signals, regen, range prerequisites,
charging prerequisites, target-80 semantics, DKK cost and completion. `CompanionPreviewTest`
covers navigation, theme switching, disconnected state and the existing demo charging pipeline.
Bench-test 800×480 and 1280×720, both themes, focus, reconnection and stale/charging transitions.
DHU restrictions/rotary certification and Play submission are blocked by eligibility; do not
claim these were validated by the standalone preview.
