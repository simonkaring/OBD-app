import SwiftUI

public struct VehicleProfilePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var vehicleData: VehicleDataManager

    @State private var selectedBrand: VehicleBrand? = nil
    @State private var brandSearchText: String = ""
    @State private var modelSearchText: String = ""

    public init(vehicleData: VehicleDataManager) {
        self.vehicleData = vehicleData
    }

    private var filteredBrands: [VehicleBrand] {
        if brandSearchText.isEmpty {
            return VehicleCatalog.brands
        } else {
            return VehicleCatalog.brands.filter { brand in
                brand.name.localizedCaseInsensitiveContains(brandSearchText) ||
                brand.models.contains { $0.modelName.localizedCaseInsensitiveContains(brandSearchText) }
            }
        }
    }

    private var filteredModels: [VehicleModelEntry] {
        let list = selectedBrand?.models ?? VehicleCatalog.allModels
        if modelSearchText.isEmpty {
            return list
        } else {
            return list.filter {
                $0.modelName.localizedCaseInsensitiveContains(modelSearchText) ||
                $0.brandName.localizedCaseInsensitiveContains(modelSearchText)
            }
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundDark.ignoresSafeArea()

                VStack(spacing: 0) {
                    if let brand = selectedBrand {
                        // Model Selection Screen
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Button {
                                    withAnimation {
                                        selectedBrand = nil
                                        modelSearchText = ""
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left")
                                        Text("Brands")
                                    }
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.electricCyan)
                                }
                                Spacer()
                                Text(brand.name)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.textPrimary)
                            }
                            .padding(.horizontal)
                            .padding(.top, 12)

                            // Search bar for models
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(Theme.textSecondary)
                                TextField("Search \(brand.name) models...", text: $modelSearchText)
                                    .foregroundColor(Theme.textPrimary)
                                if !modelSearchText.isEmpty {
                                    Button {
                                        modelSearchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                            .padding(.horizontal)

                            List(filteredModels) { model in
                                Button {
                                    vehicleData.selectVehicle(model)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: model.powertrain.badgeIcon)
                                            .font(.system(size: 20))
                                            .foregroundColor(model.powertrain == .ev ? Theme.electricCyan : (model.powertrain == .phev ? Theme.regenGreen : Theme.highPowerAmber))
                                            .frame(width: 32)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(model.modelName)
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                                .foregroundColor(Theme.textPrimary)

                                            HStack(spacing: 8) {
                                                Text(model.years)
                                                    .font(.caption)
                                                    .foregroundColor(Theme.textSecondary)

                                                if model.batteryCapacityKWh > 0 {
                                                    Text("•")
                                                        .font(.caption)
                                                        .foregroundColor(Theme.textSecondary)
                                                    Text(String(format: "%.1f kWh", model.batteryCapacityKWh))
                                                        .font(.caption)
                                                        .foregroundColor(Theme.electricCyan)
                                                }
                                            }

                                            Text(model.telemetrySupport.displayName)
                                                .font(.caption2)
                                                .foregroundColor(model.telemetrySupport == .generic ? Theme.textSecondary : Theme.regenGreen)
                                        }

                                        Spacer()

                                        Text(model.powertrain.rawValue)
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.white.opacity(0.1))
                                            .foregroundColor(Theme.textSecondary)
                                            .cornerRadius(4)
                                    }
                                }
                                .listRowBackground(Theme.cardBackground)
                            }
                            .listStyle(.plain)
                        }
                    } else {
                        // Brand Selection Screen
                        VStack(alignment: .leading, spacing: 12) {
                            // Search bar for brands
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(Theme.textSecondary)
                                TextField("Search vehicle brand or make...", text: $brandSearchText)
                                    .foregroundColor(Theme.textPrimary)
                                if !brandSearchText.isEmpty {
                                    Button {
                                        brandSearchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                            .padding(.horizontal)
                            .padding(.top, 12)

                            List(filteredBrands) { brand in
                                Button {
                                    withAnimation {
                                        selectedBrand = brand
                                    }
                                } label: {
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
                                                .foregroundColor(Theme.electricCyan)
                                                .frame(width: 32, height: 32)
                                        }
                                        #else
                                        Image(systemName: brand.iconSymbol)
                                            .font(.system(size: 22))
                                            .foregroundColor(Theme.electricCyan)
                                            .frame(width: 32, height: 32)
                                        #endif

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(brand.name)
                                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                                .foregroundColor(Theme.textPrimary)

                                            Text("\(brand.models.count) models available")
                                                .font(.caption)
                                                .foregroundColor(Theme.textSecondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                }
                                .listRowBackground(Theme.cardBackground)
                            }
                            .listStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(selectedBrand == nil ? "Select Brand" : "Select Model")
            .inlineTitleDisplayMode()
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Theme.electricCyan)
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Theme.electricCyan)
                }
                #endif
            }
        }
    }
}

#Preview("Vehicle Profile Picker Sheet") {
    VehicleProfilePickerSheet(vehicleData: VehicleDataManager())
}
