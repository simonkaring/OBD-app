import Foundation
import CoreLocation
import Combine

public struct LocationPoint: Codable, Sendable, Identifiable {
    public var id = UUID()
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double
    public let speedKmH: Double

    public init(timestamp: Date = Date(), latitude: Double, longitude: Double, altitude: Double, speedKmH: Double) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speedKmH = speedKmH
    }
}

public final class TripLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published public private(set) var currentLocation: CLLocation?
    @Published public private(set) var currentSpeedKmH: Double = 0.0
    @Published public private(set) var totalDistanceMeters: Double = 0.0
    @Published public private(set) var isTracking: Bool = false

    private let locationManager = CLLocationManager()
    private var previousLocation: CLLocation?

    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5.0
    }

    public func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestAlwaysAuthorization()
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        #if os(iOS)
        let hasAlways = manager.authorizationStatus == .authorizedAlways
        locationManager.allowsBackgroundLocationUpdates = hasAlways
        locationManager.showsBackgroundLocationIndicator = hasAlways
        #endif
    }

    public func startTracking() {
        totalDistanceMeters = 0.0
        previousLocation = nil
        isTracking = true
        locationManager.startUpdatingLocation()
    }

    public func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location

        if location.speed > 0 {
            currentSpeedKmH = location.speed * 3.6
        }

        if isTracking {
            if let prev = previousLocation {
                let delta = location.distance(from: prev)
                if delta < 500.0 { // filter GPS jumps
                    totalDistanceMeters += delta
                }
            }
            previousLocation = location
        }
    }
}
