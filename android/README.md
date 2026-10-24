# VoltLink Android

Placeholder for the Android companion app. The implementation is intentionally not
started yet: this directory only reserves the second project of the repo so the
layout (`ios/` + `android/`) is stable from day one.

When work begins, the Android app lives entirely in this directory with its own
build tooling (Gradle), package names, and CI; it must not share build files with
`ios/`. The OBD-II / UDS behavior it needs to mirror is documented in
[`ios/knowledge/`](../ios/knowledge/index.md).

The iOS app already lives in [`ios/`](../ios/README.md).
