import SwiftUI

public struct SpeedometerView: View {
    public var speedKmH: Double

    public init(speedKmH: Double) {
        self.speedKmH = speedKmH
    }

    public var body: some View {
        MetricNumericTileView(value: speedKmH, unit: "KM / H", label: "Speed")
    }
}
