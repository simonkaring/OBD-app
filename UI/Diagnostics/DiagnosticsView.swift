import SwiftUI

public struct DiagnosticsView: View {
    @ObservedObject public var dtcService: DTCScannerService
    @ObservedObject public var vehicleData: VehicleDataManager

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
                                Text("VEHICLE DIAGNOSTICS SCANNER")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.electricCyan)
                                Text(dtcService.lastScanDate == nil ? "Not Scanned Yet" : "Last Scan: \(dtcService.lastScanDate!.formatted(date: .numeric, time: .shortened))")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(Theme.textPrimary)
                                if let error = dtcService.scanErrorMessage {
                                    Text(error)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(Theme.criticalRed)
                                }
                            }
                            Spacer()

                            Button {
                                dtcService.scanDTCs(connection: vehicleData.obdConnection, isDemo: vehicleData.isDemoMode)
                            } label: {
                                HStack(spacing: 6) {
                                    if dtcService.isScanning {
                                        ProgressView().tint(.black)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    Text(dtcService.isScanning ? "Scanning..." : "Scan DTCs")
                                }
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Theme.electricCyan)
                                .foregroundColor(.black)
                                .cornerRadius(10)
                            }
                            .disabled(dtcService.isScanning)
                        }
                    }
                    .padding()
                    .glassCard()
                    .padding(.horizontal)

                    if dtcService.scannedCodes.isEmpty && !dtcService.isScanning {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 60))
                                .foregroundColor(Theme.regenGreen)
                            Text("All Systems Healthy")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.textPrimary)
                            Text("No diagnostic trouble codes detected in vehicle ECUs.")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.textSecondary)
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
                                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                                    .foregroundColor(Theme.criticalRed)

                                                Text(code.severity.rawValue)
                                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Theme.criticalRed.opacity(0.2))
                                                    .foregroundColor(Theme.criticalRed)
                                                    .cornerRadius(4)
                                            }

                                            Text(code.title)
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundColor(Theme.textPrimary)
                                        }

                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(Theme.textSecondary)
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
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.criticalRed)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .glassCard()
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 16)
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
                    dtcService.clearDTCs(connection: vehicleData.obdConnection) { success in
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
                            .font(.system(size: 32, weight: .black, design: .monospaced))
                            .foregroundColor(Theme.criticalRed)
                        Spacer()
                        Text(dtc.category)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.electricCyan.opacity(0.2))
                            .foregroundColor(Theme.electricCyan)
                            .cornerRadius(8)
                    }

                    Text(dtc.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("DESCRIPTION")
                            .font(.caption).fontWeight(.bold).foregroundColor(.gray)
                        Text(dtc.description)
                            .font(.system(size: 15))
                    }

                    if !dtc.symptoms.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("POSSIBLE SYMPTOMS")
                                .font(.caption).fontWeight(.bold).foregroundColor(.gray)
                            ForEach(dtc.symptoms, id: \.self) { sym in
                                Label(sym, systemImage: "exclamationmark.triangle")
                                    .font(.system(size: 14))
                            }
                        }
                    }

                    if !dtc.possibleFixes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RECOMMENDED REPAIR STEPS")
                                .font(.caption).fontWeight(.bold).foregroundColor(.gray)
                            ForEach(dtc.possibleFixes, id: \.self) { fix in
                                Label(fix, systemImage: "wrench.and.screwdriver")
                                    .font(.system(size: 14))
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
