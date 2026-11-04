#!/usr/bin/env bash
# Boots an Android device with the VoltLink car pane attached and opens the
# Android Auto Desktop Head Unit (DHU) against it, so the car UI can be used
# without a car.
#
#   ./scripts/car-emulator.sh                    # the only attached device
#   ./scripts/car-emulator.sh -s R5CWA0093XN     # a specific phone or emulator
#   ./scripts/car-emulator.sh -a VoltLinkAuto34  # boot or reuse that AVD
#   ./scripts/car-emulator.sh -c default_720p.ini  # another head unit display
#
# The DHU runs in the foreground: "help" lists its console commands,
# "screenshot /tmp/car.png" saves a frame, Ctrl-C quits it.
set -euo pipefail

AVD="${VOLTLINK_AVD:-VoltLinkAuto34}"
DHU_CONFIG="${VOLTLINK_DHU_CONFIG:-default_1080p.ini}"
AA_PACKAGE="${VOLTLINK_AA_PACKAGE:-com.google.android.projection.gearhead}"

usage() {
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

die() {
    echo "error: $*" >&2
    exit 1
}

SERIAL=""
BOOT_AVD=""
while getopts ":a:s:c:h" opt; do
    case "$opt" in
        a) BOOT_AVD="$OPTARG" ;;
        s) SERIAL="$OPTARG" ;;
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

# Every adb call is pinned to the selected device, so a phone and an emulator can
# be attached at the same time without any command becoming ambiguous.
adb() {
    if [[ -n "$SERIAL" ]]; then "$ADB" -s "$SERIAL" "$@"; else "$ADB" "$@"; fi
}

devices() { "$ADB" devices | awk 'NR > 1 && $2 == "device" { print $1 }'; }
avd_name() { "$ADB" -s "$1" emu avd name 2>/dev/null | head -1 | tr -d '\r'; }
booted() { [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; }

# --- target device ------------------------------------------------------------

if [[ -n "$BOOT_AVD" ]]; then
    for serial in $(devices); do
        if [[ "$(avd_name "$serial")" == "$BOOT_AVD" ]]; then
            SERIAL="$serial"
            echo "==> reusing running $BOOT_AVD ($serial)"
            break
        fi
    done
    if [[ -z "$SERIAL" ]]; then
        echo "==> booting $BOOT_AVD"
        # Detached so it survives this shell; no snapshot load/save keeps a stale
        # Android Auto session from a previous boot out of the picture.
        nohup "$EMULATOR" -avd "$BOOT_AVD" -no-snapshot-load -no-snapshot-save -no-audio -no-boot-anim \
            >"${TMPDIR:-/tmp}/voltlink-car-emulator.log" 2>&1 &
        disown || true
    fi
else
    listed="$(devices)"
    count="$(printf '%s' "$listed" | grep -c . || true)"
    if [[ -n "$SERIAL" ]]; then
        grep -qx "$SERIAL" <<<"$listed" ||
            die "device $SERIAL is not attached (attached: ${listed:-none}); run \"$0 -a $AVD\" to boot the emulator"
    elif [[ "$count" -eq 1 ]]; then
        SERIAL="$listed"
    elif [[ "$count" -eq 0 ]]; then
        die "no device attached — plug in the phone, or run \"$0 -a $AVD\" for an emulator"
    else
        die "several devices attached, pick one with -s <serial>:
$(printf '%s\n' "$listed" | sed 's/^/         /')"
    fi
fi

if [[ -z "$SERIAL" ]]; then
    echo -n "==> waiting for $BOOT_AVD to appear"
    for _ in $(seq 1 120); do
        for serial in $(devices); do
            if [[ "$(avd_name "$serial")" == "$BOOT_AVD" ]]; then SERIAL="$serial"; break; fi
        done
        [[ -n "$SERIAL" ]] && break
        echo -n "."
        sleep 3
    done
    echo
    [[ -n "$SERIAL" ]] ||
        die "$BOOT_AVD never appeared — see ${TMPDIR:-/tmp}/voltlink-car-emulator.log"
fi

echo -n "==> waiting for $SERIAL to finish booting"
for _ in $(seq 1 120); do
    if booted; then
        echo " booted"
        break
    fi
    echo -n "."
    sleep 3
done
booted || die "$SERIAL never finished booting"

# Read the list first: under pipefail a "grep -q" would close the pipe early and turn a
# match into a SIGPIPE failure, which is how this check used to deny every device.
packages="$(adb shell pm list packages 2>/dev/null | tr -d '\r' || true)"
if ! grep -qx "package:$AA_PACKAGE" <<<"$packages"; then
    die "$SERIAL has no Android Auto.
       Use a phone with Android Auto:
         $0 -s <its serial>          (list them with: adb devices -l)
       or an emulator image that already has it:
         $0 -a $AVD"
fi

# --- head unit server ---------------------------------------------------------

# The head unit server sits behind Android Auto's developer menu, which is
# enabled by tapping the version row in Settings seven times.
ui_dump() { adb exec-out uiautomator dump /dev/tty 2>/dev/null; }

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
    adb shell input tap $(((x1 + x2) / 2)) $(((y1 + y2) / 2))
}

head_unit_listening() {
    # Read the sockets first for the same reason as the package check: "grep -q" closing
    # the pipe early would fail the whole pipeline under pipefail. netstat prints the port
    # in decimal, /proc/net/tcp prints it in hex (5277 = 0x149D).
    local sockets
    sockets="$(adb shell "netstat -ltn 2>/dev/null || cat /proc/net/tcp /proc/net/tcp6 2>/dev/null" || true)"
    grep -qE '5277|149D' <<<"$sockets"
}

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
    adb shell am start -n "$AA_PACKAGE/.companion.settings.DefaultSettingsActivity" >/dev/null 2>&1
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
            adb shell input keyevent 4 >/dev/null 2>&1 || true
            echo "    already on"
            break
        fi

        start_row="$(node_bounds "Start head unit server")"
        if [[ -n "$start_row" ]]; then
            tap_bounds "$start_row"
            adb shell input keyevent 4 >/dev/null 2>&1 || true
            sleep 3
            head_unit_listening && break
            echo "    attempt $attempt did not stick, retrying"
            continue
        fi

        # No server entry: developer mode is off. Seven taps on the version row.
        adb shell input keyevent 4 >/dev/null 2>&1 || true
        for _ in $(seq 1 6); do adb shell input swipe 540 1900 540 600 200 >/dev/null 2>&1 || true; done
        version_row="$(node_bounds "Version")"
        if [[ -n "$version_row" ]]; then
            for _ in $(seq 1 7); do
                tap_bounds "$version_row"
                sleep 0.3
            done
            echo "    enabled Android Auto developer mode"
        fi
    done

    if ! head_unit_listening; then
        echo "    the status bar did not confirm it; trying anyway" >&2
    fi
fi

"$ADB" -s "$SERIAL" forward tcp:5277 tcp:5277 >/dev/null
echo "==> forwarding tcp:5277"

# --- head unit ----------------------------------------------------------------

echo "==> launching $SERIAL in the Desktop Head Unit ($DHU_CONFIG)"
echo "    console: \"help\" for commands, \"screenshot /tmp/car.png\" to save a frame, Ctrl-C to quit"
cd "$DHU_DIR"
exec ./desktop-head-unit -c "config/$DHU_CONFIG" -a 5277
