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
            if family.variants.count == 1, let model = family.variants.first {
                Button {
                    vehicleData.selectVehicle(model)
                    onSelect()
                } label: {
                    VehicleVariantRow(model: model, title: family.name, vehicleData: vehicleData)
                }
            } else {
                NavigationLink {
                    VehicleVariantPickerView(family: family, vehicleData: vehicleData, onSelect: onSelect)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(family.name)
                            .font(.headline)
                        Text("\(family.variants.count) variants")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(brand.name)
        .inlineTitleDisplayMode()
        .searchable(text: $modelSearchText, prompt: "Search \(brand.name) models")
    }
}

private struct VehicleVariantPickerView: View {
    let family: VehicleModelFamily
    @ObservedObject var vehicleData: VehicleDataManager
    let onSelect: () -> Void

    var body: some View {
        List(family.variants) { model in
            Button {
                vehicleData.selectVehicle(model)
                onSelect()
            } label: {
                VehicleVariantRow(model: model, title: model.resolvedVariantDisplayName, vehicleData: vehicleData)
            }
        }
        .navigationTitle(family.name)
        .inlineTitleDisplayMode()
    }
}

private struct VehicleVariantRow: View {
    let model: VehicleModelEntry
    let title: String
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
                    Text(model.years)
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

            if vehicleData.selectedVehicle.id == model.id {
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("Vehicle Profile Picker Sheet") {
    VehicleProfilePickerSheet(vehicleData: VehicleDataManager())
}
