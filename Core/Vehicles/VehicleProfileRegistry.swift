import Foundation

/// Identifies a registered `VehicleProfile` by a stable, `Codable`/`Hashable` value —
/// needed since `VehicleProfile` is a protocol (existential) and can't back a `Picker` selection directly.
public enum VehicleProfileID: String, CaseIterable, Identifiable, Codable, Sendable {
    case mercedesEQA250
    case hyundaiKiaEGMP
    case volkswagenMEB
    case genericOBD2

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mercedesEQA250: return "Mercedes-Benz EQA 250 (2021)"
        case .hyundaiKiaEGMP: return "Hyundai/Kia E-GMP (community profile)"
        case .volkswagenMEB: return "Volkswagen MEB (ID.3 / ID.4 / ID.Buzz)"
        case .genericOBD2: return "Generic SAE J1979 OBD-II"
        }
    }

    public func makeProfile() -> VehicleProfile {
        switch self {
        case .mercedesEQA250: return MercedesEQA250Profile()
        case .hyundaiKiaEGMP: return HyundaiKiaEGMPProfile()
        case .volkswagenMEB: return VolkswagenMEBProfile()
        case .genericOBD2: return GenericOBD2Profile()
        }
    }
}
