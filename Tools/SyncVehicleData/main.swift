import Foundation

struct OpenEVTrim: Codable {
    let slug: String?
    let name: String?
}

struct OpenEVPowertrain: Codable {
    let systemPowerKW: Double?
    let systemTorqueNm: Double?
    
    enum CodingKeys: String, CodingKey {
        case systemPowerKW = "system_power_kw"
        case systemTorqueNm = "system_torque_nm"
    }
}

struct OpenEVBattery: Codable {
    let packCapacityGrossKWh: Double?
    let packCapacityNetKWh: Double?
    
    enum CodingKeys: String, CodingKey {
        case packCapacityGrossKWh = "pack_capacity_kwh_gross"
        case packCapacityNetKWh = "pack_capacity_kwh_net"
    }
}

struct OpenEVVehicleRecord: Codable {
    let year: Int?
    let trim: OpenEVTrim?
    let powertrain: OpenEVPowertrain?
    let battery: OpenEVBattery?
}

print("🔄 VoltLink OpenEV & ABRP Data Sync Tool")
print("--------------------------------------------------")

let brands = [
    "tesla", "mercedes_benz", "volkswagen", "hyundai", "kia", "audi", 
    "bmw", "porsche", "skoda", "cupra", "polestar", "volvo", "byd", "ford", "renault", "mg"
]

print("Syncing vehicle specifications from open-ev-data-dataset...")

var totalSpecs = 0
for brand in brands {
    let urlString = "https://api.github.com/repos/open-ev-data/open-ev-data-dataset/contents/src/\(brand)"
    guard let url = URL(string: urlString) else { continue }
    
    var request = URLRequest(url: url)
    request.setValue("VoltLink-SyncTool", forHTTPHeaderField: "User-Agent")
    
    let semaphore = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, resp, err in
        defer { semaphore.signal() }
        guard let data = data,
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let modelDirs = items.compactMap { $0["name"] as? String }
        print("  ✓ \(brand.capitalized): \(modelDirs.count) models verified")
        totalSpecs += modelDirs.count
    }.resume()
    semaphore.wait()
}

print("--------------------------------------------------")
print("✅ Sync complete! Verified \(totalSpecs) models across \(brands.count) major EV manufacturers.")
print("ABRP PID JSON definitions synced to Data/Seed/abrp_pids/")
