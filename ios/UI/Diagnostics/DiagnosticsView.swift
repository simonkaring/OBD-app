import SwiftUI
import UniformTypeIdentifiers

public struct DiagnosticsView: View {
    @ObservedObject public var dtcService: DTCScannerService
    public var vehicleData: VehicleDataManager

    @State private var selectedDTC: DTCCode?
    @State private var showClearConfirmation = false
    @State private var showClearFailedAlert = false
    @State private var showCodePackImporter = false
    @State private var importNotice: String?
    @State private var importFailed = false

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
                                if let notice = dtcService.moduleScanNotice {
                                    Text(notice)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                if let notice = importNotice {
                                    Text(notice)
                                        .font(.caption)
                                        .foregroundStyle(importFailed ? Theme.criticalRed : Theme.regenGreen)
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
                            if !emissionCodes.isEmpty {
                                Section("Emission-related") {
                                    ForEach(emissionCodes) { codeRow($0) }
                                }
                            }
                            if !moduleCodes.isEmpty {
                                Section("Control-module fault memories") {
                                    ForEach(moduleCodes) { codeRow($0) }
                                    Text("Read from each module with UDS 19 02. Clearing module fault memories is not supported.")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
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
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showCodePackImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import code pack")
                }
            }
            .fileImporter(isPresented: $showCodePackImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        let count = try DTCLocalDatabase.shared.importPack(from: url)
                        importNotice = "Imported \(count) code definition\(count == 1 ? "" : "s"). Rescan to apply."
                        importFailed = false
                    } catch {
                        importNotice = error.localizedDescription
                        importFailed = true
                    }
                case .failure(let error):
                    importNotice = error.localizedDescription
                    importFailed = true
                }
            }
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

    private var emissionCodes: [DTCCode] {
        dtcService.scannedCodes.filter { $0.moduleName == nil }
    }

    private var moduleCodes: [DTCCode] {
        dtcService.scannedCodes.filter { $0.moduleName != nil }
    }

    private func codeRow(_ code: DTCCode) -> some View {
        Button {
            selectedDTC = code
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
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

                    if let module = code.moduleName {
                        Text(module)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .listRowBackground(Theme.cardBackground)
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

                    if let module = dtc.moduleName {
                        HStack {
                            Text("Module")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(module)
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    if let failure = dtc.failureTypeDescription {
                        HStack {
                            Text("Failure type")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(failure)
                                .font(.subheadline.weight(.semibold))
                        }
                    }

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

                    if let statuses = dtc.statusDescriptions, !statuses.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("FAULT STATUS")
                                .font(.caption).fontWeight(.bold).foregroundStyle(Theme.textSecondary)
                            ForEach(statuses, id: \.self) { status in
                                Label(status, systemImage: "circle.fill")
                                    .font(.subheadline)
                            }
                        }
                    }

                    if let frames = dtc.freezeFrameData, !frames.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CONDITIONS AT FAULT")
                                .font(.caption).fontWeight(.bold).foregroundStyle(Theme.textSecondary)
                            ForEach(FreezeFrameSignal.orderedValues(from: frames), id: \.label) { row in
                                HStack {
                                    Text(row.label)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    Text(row.value)
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                }
                            }
                            Text("Recorded by the ECU when this code was stored (SAE J1979 Mode 02).")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
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
