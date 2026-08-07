import SwiftUI

public struct HUDModeView: View {
    public var speedKmH: Double
    public var powerKW: Double
    public var socPct: Double
    @Binding public var isPresented: Bool

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {
                HStack {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                    Text("HEAD-UP DISPLAY MODE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.cyan)
                }
                .padding()

                Spacer()

                VStack(spacing: 10) {
                    Text(String(format: "%.0f", speedKmH))
                        .font(.system(size: 110, weight: .black, design: .rounded))
                        .foregroundColor(.green)

                    Text("KM/H")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }

                HStack(spacing: 40) {
                    VStack {
                        Text("\(Int(socPct))%")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(.cyan)
                        Text("BATTERY")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    VStack {
                        Text(String(format: "%.1f kW", powerKW))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(powerKW < 0 ? .green : .orange)
                        Text("POWER")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                Text("Reflect off windshield at night")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.bottom, 20)
            }
            .scaleEffect(x: -1, y: 1) // Mirror display horizontally for windshield reflection
        }
    }
}
