import Foundation
import CoreBluetooth
import VoltLinkEngine

let args = Array(CommandLine.arguments.dropFirst())

guard let command = args.first else {
    printUsage()
    exit(0)
}

let subArgs = Array(args.dropFirst())

switch command.lowercased() {
case "help", "-h", "--help":
    printUsage()
    
case "scan":
    await ScanCommand.run(args: subArgs)
    
case "raw", "send":
    await RawCommand.run(args: subArgs)
    
case "repl", "interactive", "i":
    await REPLCommand.run(args: subArgs)
    
case "probe", "sweep":
    await ProbeCommand.run(args: subArgs)
    
case "dtc":
    await DTCCommand.run(args: subArgs)
    
case "monitor", "live":
    await MonitorCommand.run(args: subArgs)
    
default:
    print("❌ Unknown command: '\(command)'")
    printUsage()
    exit(1)
}

func printUsage() {
    print("""
    ⚡️ VoltLink OBD Discovery & Diagnostic CLI

    USAGE:
      voltlink-cli <command> [options]

    COMMANDS:
      scan                     Scan for nearby BLE OBD adapters and print details
      raw <cmd> [cmd2 ...]     Connect and send one or more raw ELM327 / OBD / UDS commands
      repl, interactive        Start an interactive ELM327 prompt session (OBD> )
      probe [options]          Sweep UDS DIDs across ECUs to discover supported identifiers
      dtc [--clear]            Read or clear Diagnostic Trouble Codes (DTCs)
      monitor [--profile <p>]  Stream live decoded telemetry to the terminal

    PROBE OPTIONS:
      --ecu <id,...>           Comma-separated ECU addresses (default: 59,29,17)
      --start <hex>            Start DID (hex, e.g. 0100)
      --end <hex>              End DID (hex, e.g. 0150)
      --json                   Output results as JSON for automated parsing
      --all                    Include empty/negative responses (default shows positive only)

    EXAMPLES:
      swift run VoltLinkCLI scan
      swift run VoltLinkCLI raw "ATI" "ATRV" "0100"
      swift run VoltLinkCLI raw "ATSH 18DA59F1" "22 0101"
      swift run VoltLinkCLI repl
      swift run VoltLinkCLI probe --ecu 59 --start 0100 --end 0120 --json
      swift run VoltLinkCLI dtc
    """)
}
