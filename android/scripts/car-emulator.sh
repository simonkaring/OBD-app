#!/usr/bin/env bash
# Boots the emulator with an Android Auto head unit attached, so the car pane
# (car/VoltLinkCarAppService.kt) can be exercised without a car.
#
#   ./scripts/car-emulator.sh                 # VoltLinkAuto34, 1080p head unit
#   ./scripts/car-emulator.sh -a MyAvd        # another AVD
#   ./scripts/car-emulator.sh -c default_720p.ini
#
# The Desktop Head Unit runs in the foreground and reads console commands from
# this terminal ("help" lists them, "screenshot /tmp/car.png" saves a frame).
# Quit it with Ctrl-C; the emulator keeps running.
set -euo pipefail

AVD="${VOLTLINK_AVD:-VoltLinkAuto34}"
DHU_CONFIG="${VOLTLINK_DHU_CONFIG:-default_1080p.ini}"
AA_PACKAGE="com.google.android.projection.gearhead"

usage() {
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

die() {
    echo "error: $*" >&2
    exit 1
}

while getopts ":a:c:h" opt; do
    case "$opt" in
        a) AVD="$OPTARG" ;;
        c) DHU_CONFIG="$OPTARG" ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done

# The SDK comes from the environment first, then local.properties (the same
# value Gradle uses), so the script works from any working directory.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "$SDK" && -f "$ROOT/local.properties" ]]; then
    SDK="$(sed -n 's/^sdk\.dir=//p' "$ROOT/local.properties" | head -1)"
fi
[[ -n "$SDK" ]] || die "set ANDROID_HOME or ANDROID_SDK_ROOT (or add sdk.dir to android/local.properties)"

ADB="$SDK/platform-tools/adb"
EMULATOR="$SDK/emulator/emulator"
DHU_DIR="$SDK/extras/google/auto"
[[ -x "$ADB" ]] || die "missing $ADB — install the platform-tools package"
[[ -x "$EMULATOR" ]] || die "missing $EMULATOR — install the emulator package"
[[ -x "$DHU_DIR/desktop-head-unit" ]] || die \
    "missing $DHU_DIR/desktop-head-unit — install the \"Android Auto Desktop Head Unit Emulator\" SDK extra"
[[ -f "$DHU_DIR/config/$DHU_CONFIG" ]] || die \
    "unknown head unit config $DHU_CONFIG (see the files in $DHU_DIR/config)"

# --- emulator -----------------------------------------------------------------

attached() { "$ADB" devices | awk 'NR > 1 && $2 == "device" { found = 1 } END { exit !found }'; }
booted() { [[ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; }

if attached; then
    echo "==> emulator already attached, reusing it"
else
    echo "==> booting $AVD"
    # Detached so it survives this shell; no snapshot load/save keeps a stale
    # Android Auto session from a previous boot out of the picture.
    nohup "$EMULATOR" -avd "$AVD" -no-snapshot-load -no-snapshot-save -no-audio -no-boot-anim \
        >"${TMPDIR:-/tmp}/voltlink-car-emulator.log" 2>&1 &
    disown || true
fi

echo -n "==> waiting for the device to finish booting"
for _ in $(seq 1 120); do
    if attached && booted; then
        echo " booted"
        break
    fi
    echo -n "."
    sleep 3
done
attached && booted || die "the emulator never finished booting — see ${TMPDIR:-/tmp}/voltlink-car-emulator.log"

if ! "$ADB" shell pm list packages 2>/dev/null | tr -d '\r' | grep -qx "package:$AA_PACKAGE"; then
    die "Android Auto is not installed on this image. Play refuses to install it because the real
       manifest requires android.hardware.usb.accessory, so sideload it once, then re-run:
         adb install-multiple base.apk split_config.arm64_v8a.apk ..."
fi

# --- head unit server ---------------------------------------------------------

# The head unit server sits behind Android Auto's developer menu, which is
# enabled by tapping the version row in Settings seven times.
ui_dump() { "$ADB" exec-out uiautomator dump /dev/tty 2>/dev/null; }

node_bounds() {
    # $1: exact visible text of the row
    ui_dump | grep -o "[^>]*text=\"$1\"[^>]*" \
        | grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | tail -1
}

tap_bounds() {
    local bounds="$1" x1 y1 x2 y2
    bounds="${bounds#bounds=\"[}"
    bounds="${bounds%]\"}"
    x1="${bounds%%[,]*}"
    bounds="${bounds#*,}"
    y1="${bounds%%]*}"
    bounds="${bounds#*[}"
    x2="${bounds%%[,]*}"
    y2="${bounds##*,}"
    "$ADB" shell input tap $(((x1 + x2) / 2)) $(((y1 + y2) / 2))
}

head_unit_listening() { "$ADB" shell "netstat -ltn 2>/dev/null" | grep -q 5277; }

# A busy emulator sometimes throws an ANR dialog over the settings screen; it hides
# every node the automation looks for, so clear it before reading the UI.
dismiss_anr() {
    local wait_bounds
    wait_bounds="$(ui_dump | grep -o '[^>]*text="Wait"[^>]*' \
        | grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | tail -1)"
    if [[ -n "$wait_bounds" ]]; then
        tap_bounds "$wait_bounds"
        sleep 3
    fi
}

open_settings() {
    "$ADB" shell am start -n "$AA_PACKAGE/.companion.settings.DefaultSettingsActivity" >/dev/null 2>&1
    sleep 4
    dismiss_anr
}

open_overflow_menu() {
    local overflow=""
    # uiautomator needs a beat after the activity starts, and dumps occasionally come back
    # before the action bar is laid out, so retry instead of failing the whole run.
    for _ in 1 2 3 4; do
        overflow="$(ui_dump | grep -o 'content-desc="More options"[^>]*' \
            | grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | tail -1)"
        [[ -n "$overflow" ]] && break
        sleep 2
    done
    [[ -n "$overflow" ]] || return 1
    tap_bounds "$overflow"
    sleep 2
}

echo "==> starting the Android Auto head unit server"
if head_unit_listening; then
    echo "    already listening on 5277"
else
    for attempt in 1 2 3; do
        open_settings
        open_overflow_menu || die "could not open Android Auto's overflow menu"

        if [[ -n "$(node_bounds "Stop head unit server")" ]]; then
            "$ADB" shell input keyevent 4 >/dev/null 2>&1 || true
            echo "    already on"
            break
        fi

        start_row="$(node_bounds "Start head unit server")"
        if [[ -n "$start_row" ]]; then
            tap_bounds "$start_row"
            "$ADB" shell input keyevent 4 >/dev/null 2>&1 || true
            sleep 3
            head_unit_listening && break
            echo "    attempt $attempt did not stick, retrying"
            continue
        fi

        # No server entry: developer mode is off. Seven taps on the version row.
        "$ADB" shell input keyevent 4 >/dev/null 2>&1 || true
        for _ in $(seq 1 6); do "$ADB" shell input swipe 540 1900 540 600 200 >/dev/null 2>&1 || true; done
        version_row="$(node_bounds "Version")"
        if [[ -n "$version_row" ]]; then
            for _ in $(seq 1 7); do
                tap_bounds "$version_row"
                sleep 0.3
            done
            echo "    enabled Android Auto developer mode"
        fi
    done

    head_unit_listening || die \
        "the head unit server did not start — open Android Auto → ⋮ → \"Start head unit server\" by hand"
    echo "    listening on 5277"
fi

"$ADB" forward tcp:5277 tcp:5277 >/dev/null
echo "==> forwarding tcp:5277"

# --- head unit ----------------------------------------------------------------

echo "==> launching the Desktop Head Unit ($DHU_CONFIG)"
echo "    console: \"help\" for commands, \"screenshot /tmp/car.png\" to save a frame, Ctrl-C to quit"
cd "$DHU_DIR"
exec ./desktop-head-unit -c "config/$DHU_CONFIG"
