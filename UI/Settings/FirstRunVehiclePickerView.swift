import SwiftUI

/// First-run vehicle selection view shown when no vehicle has been selected yet.
/// Reuses the picker with a prominent Try Demo option.
public struct FirstRunVehiclePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var vehicleData: VehicleDataManager
    @State private var brandSearchText: String = ""
    @State private var powertrain: PowertrainType? = .ev

    public init(vehicleData: VehicleDataManager) {
        self.vehicleData = vehicleData
    }

    private var filteredBrands: [VehicleBrand] {
        let brands = VehicleCatalog.brands.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        
        let byPowertrain = brands.map { brand -> VehicleBrand in
            let filtered = powertrain.map { pt in
                brand.models.filter { $0.powertrain == pt }
            } ?? brand.models
            return VehicleBrand(id: brand.id, name: brand.name, iconSymbol: brand.iconSymbol, models: filtered)
        }.filter { !$0.models.isEmpty }
        
        if brandSearchText.isEmpty {
            return byPowertrain
        }
        
        return byPowertrain.filter { brand in
            brand.name.localizedCaseInsensitiveContains(brandSearchText) ||
            brand.modelFamilies.contains { family in
                family.name.localizedCaseInsensitiveContains(brandSearchText) ||
                family.variants.contains { variant in
                    variant.resolvedVariantDisplayName.localizedCaseInsensitiveContains(brandSearchText) ||
                    variant.modelName.localizedCaseInsensitiveContains(brandSearchText) ||
                    variant.years.localizedCaseInsensitiveContains(brandSearchText)
                }
            }
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Try Demo Button at top
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Try Demo Mode")
                                    .font(.headline)
                                Text("Simulate a vehicle without an OBD adapter")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .glassCard(cornerRadius: 12)
                    
                    Button {
                        vehicleData.toggleDemoMode(true)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Start Demo")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(12)
                        .foregroundColor(Theme.onAccent)
                        .background(Theme.electricCyan, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(12)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                .padding(12)

                // Powertrain filter
                VStack(alignment: .leading, spacing: 8) {
                    Text("Filter by Powertrain")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 12)
                    
                    HStack(spacing: 8) {
                        ForEach([.ev, .phev, .ice] as [PowertrainType], id: \.self) { pt in
                            Button {
                                powertrain = powertrain == pt ? nil : pt
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: pt.badgeIcon)
                                    Text(pt.rawValue)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background((powertrain == pt ? Theme.electricCyan : Theme.cardBackground), in: Capsule())
                                .foregroundColor(powertrain == pt ? Theme.onAccent : Theme.textPrimary)
                            }
                        }
                        Spacer()
                        if powertrain != nil {
                            Button {
                                powertrain = nil
                            } label: {
                                Text("Clear")
                                    .font(.caption)
                                    .foregroundColor(Theme.electricCyan)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }

                // Vehicle list
                List(filteredBrands) { brand in
                    NavigationLink {
                        FirstRunModelPickerView(
                            brand: brand,
                            vehicleData: vehicleData,
                            onSelect: {
                                dismiss()
                            }
                        )
                    } label: {
                        FirstRunBrandRow(brand: brand)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Select Your Vehicle")
            .inlineTitleDisplayMode()
            .searchable(text: $brandSearchText, prompt: "Search brands or models")
            .disabled(vehicleData.isCommandSessionActive)
        }
    }
}

private struct FirstRunBrandRow: View {
    let brand: VehicleBrand

    var body: some View {
        HStack(spacing: 14) {
            #if canImport(UIKit)
            if let uiImage = UIImage(named: brand.assetImageName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: brand.iconSymbol)
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
            #else
            Image(systemName: brand.iconSymbol)
                .font(.system(size: 22))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
            #endif

            VStack(alignment: .leading, spacing: 2) {
                Text(brand.name)
                    .font(.body)
                    .foregroundColor(.primary)

                Text("\(brand.modelFamilies.count) \(brand.modelFamilies.count == 1 ? "model" : "models")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FirstRunModelPickerView: View {
    let brand: VehicleBrand
    @ObservedObject var vehicleData: VehicleDataManager
    let onSelect: () -> Void
    @State private var modelSearchText: String = ""

    private var filteredFamilies: [VehicleModelFamily] {
        let families = brand.modelFamilies
        if modelSearchText.isEmpty {
            return families
        }
        return families.filter { family in
            family.name.localizedCaseInsensitiveContains(modelSearchText) ||
            family.variants.contains {
                $0.modelName.localizedCaseInsensitiveContains(modelSearchText) ||
                $0.resolvedVariantDisplayName.localizedCaseInsensitiveContains(modelSearchText) ||
                $0.years.localizedCaseInsensitiveContains(modelSearchText)
            }
        }
    }

    var body: some View {
        List(filteredFamilies) { family in
            NavigationLink {
                FirstRunYearPickerView(family: family, vehicleData: vehicleData, onSelect: onSelect)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(family.name)
                        .font(.headline)
                    Text("\(family.variants.count) \(family.variants.count == 1 ? "variant" : "variants")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(brand.name)
        .inlineTitleDisplayMode()
        .searchable(text: $modelSearchText, prompt: "Search \(brand.name) models")
    }
}

private struct FirstRunYearPickerView: View {
    let family: VehicleModelFamily
    @ObservedObject var vehicleData: VehicleDataManager
    let onSelect: () -> Void

    var body: some View {
        List {
            Section(family.name) {
                ForEach(family.modelYears, id: \.self) { year in
                    NavigationLink {
                        FirstRunVariantPickerView(family: family, modelYear: year, vehicleData: vehicleData, onSelect: onSelect)
                    } label: {
                        HStack {
                            Text(String(year))
                            Spacer()
                            if vehicleData.selectedModelYear == year,
                               family.variants.contains(where: { $0.id == vehicleData.selectedVehicle.id }) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.electricCyan)
                                    .accessibilityLabel("Selected model year")
                            }
                        }
                    }
                }
            }
            Section {
                NavigationLink("Year not specified") {
                    FirstRunVariantPickerView(family: family, modelYear: nil, vehicleData: vehicleData, onSelect: onSelect)
                }
            } footer: {
                Text("Choose the model year, which may differ from the registration year. Years reflect catalog availability; live telemetry support is shown for each variant.")
            }
        }
        .navigationTitle("Model Year")
        .inlineTitleDisplayMode()
    }
}

private struct FirstRunVariantPickerView: View {
    let family: VehicleModelFamily
    let modelYear: Int?
    @ObservedObject var vehicleData: VehicleDataManager
    let onSelect: () -> Void

    var body: some View {
        List(modelYear.map { family.variants(forModelYear: $0) } ?? family.variants) { model in
            Button {
                if vehicleData.selectVehicle(model, modelYear: modelYear) {
                    onSelect()
                }
            } label: {
                FirstRunVariantRow(model: model, title: model.resolvedVariantDisplayName, modelYear: modelYear, vehicleData: vehicleData)
            }
        }
        .navigationTitle(family.name + (modelYear.map { " · \($0)" } ?? ""))
        .inlineTitleDisplayMode()
    }
}

private struct FirstRunVariantRow: View {
    let model: VehicleModelEntry
    let title: String
    let modelYear: Int?
    @ObservedObject var vehicleData: VehicleDataManager

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: model.powertrain.badgeIcon)
                            .font(.caption2)
                        Text(model.powertrain.rawValue)
                            .font(.caption2)
                    }
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .foregroundColor(.secondary)
                    .clipShape(Capsule())
                }

                HStack(spacing: 6) {
                    Text(modelYear.map { String($0) } ?? model.years)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if model.batteryCapacityKWh > 0 {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f kWh", model.batteryCapacityKWh))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 4) {
                    Label(model.telemetrySupport.displayName, systemImage: model.telemetrySupport == .verified ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundColor(model.telemetrySupport == .verified ? Theme.regenGreen : .secondary)
                }

                if let notes = model.notes {
                    Text(notes)
                        .font(.caption2)
                        .foregroundColor(Theme.highPowerAmber)
                }
            }

            if vehicleData.selectedVehicle.id == model.id && vehicleData.selectedModelYear == modelYear {
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .accessibilityLabel("Selected vehicle")
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("First Run Vehicle Picker") {
    FirstRunVehiclePickerView(vehicleData: VehicleDataManager())
}
