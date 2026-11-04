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

# Android Auto's head unit server is DeveloperHeadUnitNetworkService, and it is not
# exported: an ordinary shell gets "Requires permission not exported from uid …", and
# both a retail phone and the Play emulator image are user/release-keys builds, so
# `adb root` cannot lift that either. There is no start broadcast, and the server does
# not come back by itself once Android Auto stops. So: start it from the shell when the
# image allows it (userdebug or root), and otherwise ask for the one menu toggle rather
# than driving the UI with uiautomator taps.
HU_SERVICE="com.google.android.projection.gearhead/.companion.DeveloperHeadUnitNetworkService"

head_unit_listening() {
    # Read the sockets first for the same reason as the package check: "grep -q" closing
    # the pipe early would fail the whole pipeline under pipefail. netstat prints the port
    # in decimal, /proc/net/tcp prints it in hex (5277 = 0x149D).
    local sockets
    sockets="$(adb shell "netstat -ltn 2>/dev/null || cat /proc/net/tcp /proc/net/tcp6 2>/dev/null" || true)"
    grep -qE '5277|149D' <<<"$sockets"
}

echo "==> head unit server"
if head_unit_listening; then
    echo "    already listening on 5277"
else
    adb shell am start-foreground-service -n "$HU_SERVICE" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5; do
        head_unit_listening && break
        sleep 1
    done

    if head_unit_listening; then
        echo "    started from the shell"
    else
        # Leave the user on the screen that holds the toggle; it is two taps from here.
        adb shell am start -n "$AA_PACKAGE/.companion.settings.DefaultSettingsActivity" >/dev/null 2>&1 || true
        die "the head unit server is off, and only Android Auto itself may start it.
       On the phone: Android Auto > menu (top right) > Start head unit server, then re-run
       this. It stays up until Android Auto is force-stopped or the phone restarts."
    fi
fi

"$ADB" -s "$SERIAL" forward tcp:5277 tcp:5277 >/dev/null
echo "==> forwarding tcp:5277"

# --- head unit ----------------------------------------------------------------

echo "==> launching $SERIAL in the Desktop Head Unit ($DHU_CONFIG)"
echo "    console: \"help\" for commands, \"screenshot /tmp/car.png\" to save a frame, Ctrl-C to quit"
cd "$DHU_DIR"
exec ./desktop-head-unit -c "config/$DHU_CONFIG" -a 5277
