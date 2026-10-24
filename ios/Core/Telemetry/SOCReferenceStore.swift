import Foundation

/// Persists the dashboard SOC reference per vehicle, model year, and profile. Each
/// selection keeps its own offset so switching profiles never silently re-scales the
/// battery readout.
struct SOCReferenceStore {
    let defaults: UserDefaults?
    let vehicleID: String
    let modelYear: Int?
    let profileID: VehicleProfileID

    var key: String {
        "socReferenceOffset.\(vehicleID).\(modelYear.map(String.init) ?? "unspecified").\(profileID.rawValue)"
    }

    func load() -> Double? {
        guard let offset = defaults?.object(forKey: key) as? Double else { return nil }
        return offset.isFinite && (-100...100).contains(offset) ? offset : nil
    }

    func save(_ offset: Double) {
        defaults?.set(offset, forKey: key)
    }

    func reset() {
        defaults?.removeObject(forKey: key)
    }
}
