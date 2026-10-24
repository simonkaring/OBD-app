import SwiftUI

public struct DiagnosticsView: View {
    @ObservedObject public var dtcService: DTCScannerService
    public var vehicleData: VehicleDataManager

    @State private var selectedDTC: DTCCode?
    @State private var showClearConfirmation = false
    @State private var showClearFailedAlert = false

    public init(dtcService: DTCScannerService, vehicleData: VehicleDataManager) {
        self.dtcService = dtcService
        self.vehicleData = vehicleData
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundDark.ignoresSafeArea()

                VStack(spacing: 16) {
                    // Scan Status Banner
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Vehicle diagnostics")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                Text(
                                    dtcService.lastScanDate == nil
                                        ? "Not Scanned Yet" : "Last Scan: \(dtcService.lastScanDate!.formatted(date: .numeric, time: .shortened))"
                                )
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                                if let error = dtcService.scanErrorMessage {
                                    Text(error)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.criticalRed)
                                }
                            }
                            Spacer()

                            Button {
                                dtcService.scanDTCs(vehicleData: vehicleData)
                            } label: {
                                HStack(spacing: 6) {
                                    if dtcService.isScanning {
                                        ProgressView().tint(.black)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    Text(dtcService.isScanning ? "Scanning..." : "Scan DTCs")
                                }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Theme.electricCyan)
                                .foregroundStyle(Theme.onAccent)
                                .cornerRadius(10)
                            }
                            .disabled(dtcService.isScanning || vehicleData.isCommandSessionActive || !vehicleData.connectionState.isConnected)
                        }
                    }
                    .padding()
                    .glassCard()
                    .padding(.horizontal)

                    if dtcService.scannedCodes.isEmpty && !dtcService.isScanning {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: dtcService.scanSucceeded ? "checkmark.shield.fill" : "stethoscope")
                                .font(.system(size: 60))
                                .foregroundStyle(dtcService.scanSucceeded ? Theme.regenGreen : Theme.textSecondary)
                            Text(dtcService.scanSucceeded ? "No Fault Codes Detected" : "Scan Required")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(dtcService.healthSummary)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(dtcService.scannedCodes) { code in
                                Button {
                                    selectedDTC = code
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(code.code)
                                                    .font(.headline.weight(.bold).monospaced())
                                                    .foregroundStyle(Theme.criticalRed)

                                                Text(code.severity.rawValue)
                                                    .font(.caption)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Theme.criticalRed.opacity(0.2))
                                                    .foregroundStyle(Theme.criticalRed)
                                                    .cornerRadius(4)
                                            }

                                            Text(code.title)
                                                .font(.headline)
                                                .foregroundStyle(Theme.textPrimary)
                                        }

                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                .listRowBackground(Theme.cardBackground)
                            }
                        }
                        .listStyle(.plain)
                        .padding(.horizontal)

                        Button {
                            showClearConfirmation = true
                        } label: {
                            Text("Clear Diagnostic Trouble Codes")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.criticalRed)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .glassCard()
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                        .disabled(dtcService.isScanning || vehicleData.isCommandSessionActive)
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .inlineTitleDisplayMode()
            .sheet(item: $selectedDTC) { dtc in
                DTCDetailSheet(dtc: dtc)
            }
            .alert("Clear Diagnostic Codes?", isPresented: $showClearConfirmation) {
                Button("Clear Codes", role: .destructive) {
                    dtcService.clearDTCs(vehicleData: vehicleData) { success in
                        if !success {
                            showClearFailedAlert = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clearing codes will reset vehicle ECU diagnostic logs and turn off check warning lights. Ensure vehicle speed is 0 km/h before clearing.")
            }
            .alert("Clear Failed", isPresented: $showClearFailedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The vehicle did not confirm the codes were cleared. Try again with the ignition on and the vehicle stationary.")
            }
        }
    }
}

public struct DTCDetailSheet: View {
    public let dtc: DTCCode
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(dtc.code)
                            .font(.largeTitle.weight(.black).monospaced())
                            .foregroundStyle(Theme.criticalRed)
                        Spacer()
                        Text(dtc.category)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.electricCyan.opacity(0.2))
                            .foregroundStyle(Theme.electricCyan)
                            .cornerRadius(8)
                    }

                    Text(dtc.title)
                        .font(.title3.weight(.semibold))

                    if let source = dtc.definitionSource {
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("DESCRIPTION")
                            .font(.caption).fontWeight(.bold).foregroundStyle(Theme.textSecondary)
                        Text(dtc.description)
                            .font(.subheadline)
                    }

                    if !dtc.symptoms.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("POSSIBLE SYMPTOMS")
                                .font(.caption).fontWeight(.bold).foregroundStyle(Theme.textSecondary)
                            ForEach(dtc.symptoms, id: \.self) { sym in
                                Label(sym, systemImage: "exclamationmark.triangle")
                                    .font(.subheadline)
                            }
                        }
                    }

                    if !dtc.possibleFixes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RECOMMENDED REPAIR STEPS")
                                .font(.caption).fontWeight(.bold).foregroundStyle(Theme.textSecondary)
                            ForEach(dtc.possibleFixes, id: \.self) { fix in
                                Label(fix, systemImage: "wrench.and.screwdriver")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Code Details")
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview("Diagnostics View") {
    DiagnosticsView(
        dtcService: DTCScannerService(),
        vehicleData: VehicleDataManager()
    )
}
