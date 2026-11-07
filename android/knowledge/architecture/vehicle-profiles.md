---
type: Architecture
title: "Vehicle profiles"
description: "The VehicleProfile contract, the registry IDs, how ABRP community definitions are loaded, and how to add a car."
tags: [architecture, vehicle-profile, obd]
status: stable
sources:
- id: contract
  resource: ../app/src/main/java/com/simonkaring/voltlink/core/vehicles/VehicleProfile.kt
  title: VehicleProfile contract and compiled-in profiles
- id: registry
  resource: ../app/src/main/java/com/simonkaring/voltlink/core/vehicles/VehicleProfileRegistry.kt
  title: Vehicle profile registry
- id: abrp
  resource: ../app/src/main/java/com/simonkaring/voltlink/core/vehicles/AbrpProfile.kt
  title: ABRP definition parser and loader
---

# Contract

`core/vehicles/VehicleProfile.kt` defines one interface: a name, whether the car is electric,
usable pack capacity, initialization and polling commands, the set of `TelemetryMetric`s it can
produce, and `parseResponse`/`parseResponses` to decode a reply. Profiles are stateless and
`Sendable` by construction; they never touch the connection.

# Registry

`VehicleProfileId` is the stable identity the UI and settings persist (`MERCEDES_EQ_A250`,
`VOLKSWAGEN_MEB`, `GENERIC_OBD2`, …). `makeProfile()` maps an ID to an implementation:

- Hand-written decoders live in `VehicleProfile.kt` (`MercedesEqa250Profile`,
  `MercedesEqaObdbProfile`, `VolkswagenMebProfile`, `HyundaiKiaEgmpProfile`,
  `NissanLeafZe1Profile`, the generic J1979 pair).
- Everything else carries an `abrpFilename` and is resolved through `AbrpProfileLoader`.
- If a bundled definition cannot be read, the ID falls back to `GenericEvProfile` instead of
  failing the selection.

Fresh installs start on `MERCEDES_EQ_A_OBDb`: the app is EQA-first and the community signal set
is the richest decoder for that car. Every other profile stays one tap away in the picker, and a
stored choice always wins over the default. The default dashboard carries two community tiles
(motor and drive-unit temperature) that `DashboardLayout.adapted()` drops for any profile that
cannot report them.

`VehicleCatalog.profileOptions` groups catalog rows by `modelFamilyId`, so Settings can list the
alternative decoders for the selected car — the EQA's verified and OBDb rows, for example — each
with the count and names of the metrics it reports. Choosing one goes through `selectVehicle`,
keeping the catalog row, the active profile and the re-initialisation in step.

`VehicleCatalog.profileAlternatives` covers the opposite case: community ABRP tables that decode a
car the catalog already binds to a compiled-in profile (`VOLKSWAGEN_MEB_ABRP` for every MEB model,
`HYUNDAI_KIA_EGMP_ABRP` for IONIQ 5 / 6 / 9 and EV6 / EV9). They have no catalog row, so Settings
appends them to the same comparison and switches with `selectProfile(..., keepVehicle = true)`:
the picked car and its stored name stay, only the decoder changes. The ABRP tables report more
signals than the built-in decoders (cell temperatures and voltages, charged energy, DC-fast-charge
state), but they are community-sourced and unverified on hardware — label them accordingly and let
the user compare rather than replacing the compiled-in default.

# ABRP definitions

`assets/abrp_pids/*.json` hold community PID tables. `AbrpProfileLoader` parses one file into
`AbrpProfileDefinition` and wraps it in `AbrpGenericProfile`. The loader needs an asset reader,
installed from `AssetManager` at startup; without a reader — JVM tests, the OKF generator — it
reports no definition and callers get the generic decoder. Tests that need real definitions
call `AbrpProfileLoader.install { path -> ... }`, which is how
[the knowledge bundle](/architecture/testing.md) lists real commands.

# Adding a car

1. Add an ID to `VehicleProfileId` with its display name (and the ABRP filename, if the
   decoding comes from a bundled table).
2. Either write the decoder in `VehicleProfile.kt` and add it to the `makeProfile()` `when`, or
   ship the JSON table under `assets/abrp_pids/` and register the file name.
3. Add the car to `assets/vehicle_catalog.json` so the picker's brand → model → year drill-down
   can find it, with `profileID` set to the new ID.
4. Test the decoder against captured responses in `app/src/test/.../core/vehicles`.
5. Regenerate both documentation bundles — see [Testing](/architecture/testing.md).

# Honesty rules

A profile only advertises metrics it can actually decode. Community definitions are marked as
such in the picker and carry their provenance (OBDb, iternio/ev-obd-pids, OVMS) in the source;
do not promote a plausible-looking byte offset to "verified" without a capture from the car.

Related: [Data flow](/architecture/data-flow.md), [Testing](/architecture/testing.md).
