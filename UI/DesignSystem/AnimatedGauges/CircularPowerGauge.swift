import SwiftUI

public struct CircularPowerGauge: View {
    public var powerKW: Double // -50 (Regen) to +150 (Power)
    public var maxPowerKW: Double = 150.0
    public var maxRegenKW: Double = 50.0

    public init(powerKW: Double) {
        self.powerKW = powerKW
    }

    public var body: some View {
        MetricDialView(
            value: powerKW,
            range: 0...maxPowerKW,
            mode: .bidirectional(negativeMax: maxRegenKW),
            unit: "kW",
            label: "Power"
        )
    }
}
