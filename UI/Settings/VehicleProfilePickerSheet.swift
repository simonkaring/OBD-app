import SwiftUI

public struct VehicleProfilePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var vehicleData: VehicleDataManager

    @State private var brandSearchText: String = ""

    public init(vehicleData: VehicleDataManager) {
        self.vehicleData = vehicleData
    }

    private var filteredBrands: [VehicleBrand] {
        let brands = VehicleCatalog.brands.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if brandSearchText.isEmpty {
            return brands
        } else {
            return brands.filter { brand in
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
    }

    public var body: some View {
        NavigationStack {
            List(filteredBrands) { brand in
                NavigationLink {
                    VehicleModelPickerView(
                        brand: brand,
                        vehicleData: vehicleData,
                        onSelect: {
                            dismiss()
                        }
                    )
                } label: {
                    BrandRow(brand: brand)
                }
            }
            .navigationTitle("Select Brand")
            .inlineTitleDisplayMode()
            .searchable(text: $brandSearchText, prompt: "Search brands")
            .disabled(vehicleData.isCommandSessionActive)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct BrandRow: View {
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

private struct VehicleModelPickerView: View {
    let brand: VehicleBrand
    @ObservedObject var vehicleData: VehicleDataManager
    let onSelect: () -> Void

    @State private var modelSearchText: String = ""

    private var filteredFamilies: [VehicleModelFamily] {
        let families = brand.modelFamilies
        if modelSearchText.isEmpty {
            return families
        } else {
            return families.filter { family in
                family.name.localizedCaseInsensitiveContains(modelSearchText) ||
                family.variants.contains {
                    $0.modelName.localizedCaseInsensitiveContains(modelSearchText) ||
                    $0.resolvedVariantDisplayName.localizedCaseInsensitiveContains(modelSearchText) ||
                    $0.years.localizedCaseInsensitiveContains(modelSearchText)
                }
            }
        }
    }

    var body: some View {
        List(filteredFamilies) { family in
            NavigationLink {
                VehicleYearPickerView(family: family, vehicleData: vehicleData, onSelect: onSelect)
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

private struct VehicleYearPickerView: View {
    let family: VehicleModelFamily
    @ObservedObject var vehicleData: VehicleDataManager
    let onSelect: () -> Void

    var body: some View {
        List {
            Section(family.name) {
                ForEach(family.modelYears, id: \.self) { year in
                    NavigationLink {
                        VehicleVariantPickerView(family: family, modelYear: year, vehicleData: vehicleData, onSelect: onSelect)
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
                    VehicleVariantPickerView(family: family, modelYear: nil, vehicleData: vehicleData, onSelect: onSelect)
                }
            } footer: {
                Text("Choose the model year, which may differ from the registration year. Years reflect catalog availability; live telemetry support is shown for each variant.")
            }
        }
        .navigationTitle("Model Year")
        .inlineTitleDisplayMode()
    }
}

private struct VehicleVariantPickerView: View {
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
                VehicleVariantRow(model: model, title: model.resolvedVariantDisplayName, modelYear: modelYear, vehicleData: vehicleData)
            }
        }
        .navigationTitle(family.name + (modelYear.map { " · \($0)" } ?? ""))
        .inlineTitleDisplayMode()
    }
}

private struct VehicleVariantRow: View {
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

                    Text(model.powertrain.rawValue)
                        .font(.caption2)
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

                Text(model.telemetrySupport.displayName)
                    .font(.caption)
                    .foregroundColor(model.telemetrySupport == .verified ? .green : .secondary)

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

#Preview("Vehicle Profile Picker Sheet") {
    VehicleProfilePickerSheet(vehicleData: VehicleDataManager())
}
