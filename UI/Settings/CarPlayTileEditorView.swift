import SwiftUI

/// Reorder/add/remove editor for CarPlay's grid tiles, reusing the same list-editor
/// pattern as `DashboardCustomizationSheet`.
public struct CarPlayTileEditorView: View {
    @ObservedObject public var vehicleData: VehicleDataManager
    @AppStorage(CarPlayLayout.storageKey) private var layout: CarPlayLayout = .default
    @State private var showAddTile = false

    public init(vehicleData: VehicleDataManager) {
        self.vehicleData = vehicleData
    }

    public var body: some View {
        List {
            Section {
                ForEach(layout.tiles, id: \.self) { tile in
                    Label(title(for: tile), systemImage: icon(for: tile))
                }
                .onMove { layout.tiles.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { layout.tiles.remove(atOffsets: $0) }
            } footer: {
                Text("CarPlay items display telemetry text cards with speed & power dials. Up to \(CarPlayLayout.maxTiles) items.")
            }
        }
        .navigationTitle("CarPlay Tiles")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    #if os(iOS)
                    EditButton()
                    #endif
                    Button {
                        showAddTile = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(layout.tiles.count >= CarPlayLayout.maxTiles)
                }
            }
        }
        .sheet(isPresented: $showAddTile) {
            AddCarPlayTileSheet(profile: vehicleData.selectedProfile) { newTile in
                if layout.tiles.count < CarPlayLayout.maxTiles {
                    layout.tiles.append(newTile)
                }
            }
        }
    }

    private func title(for tile: CarPlayTileKind) -> String {
        switch tile {
        case .metric(let metric): return metric.displayName
        case .health: return "System Health"
        }
    }

    private func icon(for tile: CarPlayTileKind) -> String {
        switch tile {
        case .metric(let metric): return metric.sfSymbolName
        case .health: return "checkmark.shield.fill"
        }
    }
}

private struct AddCarPlayTileSheet: View {
    let profile: VehicleProfile
    let onAdd: (CarPlayTileKind) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onAdd(.health)
                    dismiss()
                } label: {
                    Label("System Health", systemImage: "checkmark.shield.fill")
                }

                ForEach(TelemetryMetric.allCases.filter { profile.supportedMetrics.contains($0) }) { metric in
                    Button {
                        onAdd(.metric(metric))
                        dismiss()
                    } label: {
                        Label(metric.displayName, systemImage: metric.sfSymbolName)
                    }
                }
            }
            .navigationTitle("Add Tile")
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
