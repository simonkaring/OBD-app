#!/usr/bin/env python3
"""Capture labelled Mercedes EQA BMS responses through VoltLinkCLI."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / ".build" / "debug" / "VoltLinkCLI"
RESULT_RE = re.compile(r"^\[(\d+)ms\] (.*?) ➔ (.*)$")
INIT_COMMANDS = [
    "AT Z",
    "AT E0",
    "AT L0",
    "AT S1",
    "AT H1",
    "AT CAF 1",
    "AT SP 7",
    "AT CP 18",
    "AT ST FF",
    "ATCRA 18DAF159",
    "AT SH 18DA59F1",
    "AT FCSH 18DA59F1",
    "AT FCSD 300000",
    "AT FCSM 1",
]
POLL_COMMANDS = ["22010A", "22010B", "22010C", "220210"]


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Capture EQA voltage/current/status/SOC candidates over BLE."
    )
    parser.add_argument("--soc", type=float, required=True, help="SOC shown by the car")
    parser.add_argument("--samples", type=int, default=20, help="Poll cycles (default: 20)")
    parser.add_argument("--ambient", type=float, help="Ambient temperature in C")
    parser.add_argument("--battery-temp", type=float, help="Independent battery temperature in C")
    parser.add_argument("--charger-kw", type=float, help="Power shown by the charger")
    parser.add_argument("--plugged", choices=["yes", "no", "unknown"], default="unknown")
    parser.add_argument("--charging", choices=["ac", "dc", "no", "unknown"], default="unknown")
    parser.add_argument(
        "--vehicle-state",
        choices=["off", "parked", "ready", "driving", "charging"],
        default="parked",
    )
    parser.add_argument("--note", default="", help="Free-form capture note")
    parser.add_argument("--output", type=Path, help="Output JSON path")
    parser.add_argument("--dry-run", action="store_true", help="Print commands without using BLE")
    args = parser.parse_args()
    if not 0 <= args.soc <= 100:
        parser.error("--soc must be between 0 and 100")
    if args.samples < 1:
        parser.error("--samples must be positive")
    if args.charger_kw is not None and args.charger_kw < 0:
        parser.error("--charger-kw cannot be negative")
    return args


def build_cli() -> None:
    if CLI.exists():
        return
    subprocess.run(
        ["swift", "build", "--product", "VoltLinkCLI"],
        cwd=ROOT,
        check=True,
    )


def parse_results(stdout: str) -> list[dict[str, object]]:
    results: list[dict[str, object]] = []
    for line in stdout.splitlines():
        match = RESULT_RE.match(line.strip())
        if not match:
            continue
        duration, command, response = match.groups()
        results.append(
            {
                "sequence": len(results),
                "durationMs": int(duration),
                "command": command.strip(),
                "rawResponse": response.strip(),
            }
        )
    return results


def main() -> int:
    args = arguments()
    commands = INIT_COMMANDS + POLL_COMMANDS * args.samples
    if args.dry_run:
        print("\n".join(commands))
        return 0

    build_cli()
    started = datetime.now(timezone.utc)
    process = subprocess.run(
        [str(CLI), "raw", *commands],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    finished = datetime.now(timezone.utc)
    print(process.stdout, end="")
    if process.stderr:
        print(process.stderr, file=sys.stderr, end="")

    results = parse_results(process.stdout)
    poll_results = [item for item in results if item["command"] in POLL_COMMANDS]
    payload = {
        "schemaVersion": 1,
        "startedAt": started.isoformat(timespec="milliseconds"),
        "finishedAt": finished.isoformat(timespec="milliseconds"),
        "references": {
            "clusterSOCPercent": args.soc,
            "ambientTemperatureC": args.ambient,
            "batteryTemperatureC": args.battery_temp,
            "chargerPowerKW": args.charger_kw,
            "plugged": args.plugged,
            "chargingType": args.charging,
            "vehicleState": args.vehicle_state,
            "note": args.note,
        },
        "pollCyclesRequested": args.samples,
        "results": poll_results,
        "completeCLIOutput": process.stdout,
        "exitCode": process.returncode,
    }
    timestamp = started.strftime("%Y%m%dT%H%M%SZ")
    output = args.output or ROOT / "scratch" / "captures" / f"eqa_capture_{timestamp}.json"
    output = output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(f"\nSaved {len(poll_results)} EQA responses to {output}")
    if process.returncode != 0:
        return process.returncode
    if len(poll_results) != args.samples * len(POLL_COMMANDS):
        print("Capture was incomplete; inspect the saved CLI output.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
