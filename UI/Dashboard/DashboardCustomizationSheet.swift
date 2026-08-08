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
                    Text("Half Width").tag(WidgetSize.medium)
                    Text("Full Width").tag(WidgetSize.large)
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

    @State private var searchText = ""
    @State private var selectedSize: WidgetSize = .medium
    @State private var selectedStyle: MetricDisplayStyle = .dial
    @State private var chartSeries: Set<TelemetryMetric> = [.power, .speed]

    public init(profile: VehicleProfile, onAdd: @escaping (DashboardWidgetConfig) -> Void) {
        self.profile = profile
        self.onAdd = onAdd
    }

    private var filteredMetrics: [TelemetryMetric] {
        let supported = TelemetryMetric.allCases.filter { profile.supportedMetrics.contains($0) }
        if searchText.isEmpty {
            return supported
        }
        return supported.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundDark.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // iOS Gallery Search & Selectors
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(Theme.textSecondary)
                                TextField("Search widgets", text: $searchText)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.textPrimary)
                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)

                            // Size & Style Selectors
                            HStack(spacing: 12) {
                                Picker("Size", selection: $selectedSize) {
                                    Text("Half Width").tag(WidgetSize.medium)
                                    Text("Full Width").tag(WidgetSize.large)
                                }
                                .pickerStyle(.segmented)

                                Picker("Style", selection: $selectedStyle) {
                                    ForEach(MetricDisplayStyle.allCases) { style in
                                        Text(style.displayName).tag(style)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        .padding(.horizontal)

                        // Metric Widget Cards (iOS Widget Gallery Style)
                        VStack(alignment: .leading, spacing: 14) {
                            Text("TELEMETRY METRICS")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.electricCyan)
                                .padding(.horizontal)

                            ForEach(filteredMetrics) { metric in
                                iosWidgetCard(for: metric)
                            }
                        }

                        // Chart Widget Section
                        VStack(alignment: .leading, spacing: 14) {
                            Text("LIVE TELEMETRY CHART")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.electricCyan)
                                .padding(.horizontal)

                            chartWidgetCard
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Widget Gallery")
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            }
        }
    }

    @ViewBuilder
    private func iosWidgetCard(for metric: TelemetryMetric) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.electricCyan.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: metric.sfSymbolName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.electricCyan)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.displayName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.textPrimary)
                    Text("Unit: \(metric.unitSymbol) • Display as \(selectedStyle.displayName)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                }

                Spacer()

                Button {
                    onAdd(DashboardWidgetConfig(kind: .metric(metric), style: selectedStyle, size: selectedSize))
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.electricCyan)
                    .foregroundColor(.black)
                    .cornerRadius(20)
                }
            }

            // Visual Mini Preview Box
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.electricCyan.opacity(0.2), lineWidth: 1)
                    )

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedSize.rawValue.uppercased() + " PREVIEW")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.electricCyan)
                        Text(metric.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.textPrimary)
                    }
                    Spacer()

                    Image(systemName: selectedStyle == .dial ? "gauge.with.needle.fill" : (selectedStyle == .bar ? "chart.bar.fill" : "number.circle.fill"))
                        .font(.system(size: 24))
                        .foregroundColor(Theme.electricCyan)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
        .padding(.horizontal)
    }

    private var chartWidgetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.highPowerAmber.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.highPowerAmber)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Telemetry Chart")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.textPrimary)
                    Text("Plot up to 2 telemetry metrics over time")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                }

                Spacer()

                Button {
                    onAdd(DashboardWidgetConfig(kind: .chart(series: Array(chartSeries)), style: .numeric, size: .large))
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.highPowerAmber)
                    .foregroundColor(.black)
                    .cornerRadius(20)
                }
                .disabled(chartSeries.isEmpty)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Select Series Metrics:")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textSecondary)

                HStack(spacing: 8) {
                    ForEach(filteredMetrics.prefix(4)) { metric in
                        Button {
                            if chartSeries.contains(metric) {
                                chartSeries.remove(metric)
                            } else if chartSeries.count < 2 {
                                chartSeries.insert(metric)
                            }
                        } label: {
                            Text(metric.displayName)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(chartSeries.contains(metric) ? Theme.highPowerAmber.opacity(0.3) : Color.white.opacity(0.08))
                                .foregroundColor(chartSeries.contains(metric) ? Theme.highPowerAmber : Theme.textSecondary)
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
        .padding(.horizontal)
    }
}
