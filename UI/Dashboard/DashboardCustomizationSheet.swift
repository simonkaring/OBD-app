import SwiftUI

/// Native reorder/add/remove editor for the dashboard's widget layout.
public struct DashboardCustomizationSheet: View {
    @Binding public var layout: DashboardLayout
    public var profile: VehicleProfile
    @Environment(\.dismiss) private var dismiss
    @State private var showAddWidget = false

    public init(layout: Binding<DashboardLayout>, profile: VehicleProfile) {
        self._layout = layout
        self.profile = profile
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($layout.widgets) { $widget in
                        widgetRow(for: $widget)
                    }
                    .onMove { layout.widgets.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { layout.widgets.remove(atOffsets: $0) }
                } footer: {
                    Text("Drag to reorder. Swipe to remove.")
                }
            }
            .navigationTitle("Customize Dashboard")
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        #if os(iOS)
                        EditButton()
                        #endif
                        Button {
                            showAddWidget = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddWidget) {
                AddDashboardWidgetSheet(profile: profile) { newWidget in
                    layout.widgets.append(newWidget)
                }
            }
        }
    }

    @ViewBuilder
    private func widgetRow(for widget: Binding<DashboardWidgetConfig>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(widgetTitle(widget.wrappedValue))
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            HStack {
                if case .metric = widget.wrappedValue.kind {
                    Picker("Style", selection: widget.style) {
                        ForEach(MetricDisplayStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Spacer()

                Picker("Size", selection: widget.size) {
                    ForEach(WidgetSize.allCases) { size in
                        Text(size.rawValue.capitalized).tag(size)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(.vertical, 4)
    }

    private func widgetTitle(_ config: DashboardWidgetConfig) -> String {
        switch config.kind {
        case .metric(let metric): return metric.displayName
        case .chart(let series): return "Chart (\(series.map(\.displayName).joined(separator: " & ")))"
        }
    }
}

public struct AddDashboardWidgetSheet: View {
    public let profile: VehicleProfile
    public let onAdd: (DashboardWidgetConfig) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chartSeries: Set<TelemetryMetric> = [.power]

    public init(profile: VehicleProfile, onAdd: @escaping (DashboardWidgetConfig) -> Void) {
        self.profile = profile
        self.onAdd = onAdd
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Metrics") {
                    ForEach(TelemetryMetric.allCases.filter { profile.supportedMetrics.contains($0) }) { metric in
                        Button {
                            onAdd(DashboardWidgetConfig(kind: .metric(metric), style: .numeric, size: .small))
                            dismiss()
                        } label: {
                            Label(metric.displayName, systemImage: metric.sfSymbolName)
                        }
                    }
                }

                Section {
                    ForEach(TelemetryMetric.allCases.filter { profile.supportedMetrics.contains($0) }) { metric in
                        Toggle(metric.displayName, isOn: Binding(
                            get: { chartSeries.contains(metric) },
                            set: { isOn in
                                if isOn {
                                    if chartSeries.count < 2 { chartSeries.insert(metric) }
                                } else {
                                    chartSeries.remove(metric)
                                }
                            }
                        ))
                    }

                    Button("Add Chart") {
                        onAdd(DashboardWidgetConfig(kind: .chart(series: Array(chartSeries)), style: .numeric, size: .large))
                        dismiss()
                    }
                    .disabled(chartSeries.isEmpty)
                } header: {
                    Text("Chart (up to 2 metrics)")
                }
            }
            .navigationTitle("Add Widget")
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
