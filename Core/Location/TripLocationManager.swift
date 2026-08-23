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
    @Published public private(set) var authorizationStatus: CLAuthorizationStatus

    private let locationManager = CLLocationManager()
    private var previousLocation: CLLocation?
    private var trackingRequested = false

    private static let maximumLocationAge: TimeInterval = 15
    private static let maximumHorizontalAccuracyMeters: CLLocationAccuracy = 100
    private static let maximumDistanceJumpMeters: CLLocationDistance = 500

    public override init() {
        self.authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5.0
        updateBackgroundLocationSettings()
    }

    public func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    public func requestAlwaysAuthorization() {
        #if os(iOS)
        guard authorizationStatus == .authorizedWhenInUse else { return }
        #endif
        locationManager.requestAlwaysAuthorization()
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        updateBackgroundLocationSettings()

        if trackingRequested, isAuthorized, !isTracking {
            isTracking = true
            locationManager.startUpdatingLocation()
        } else if !isAuthorized {
            isTracking = false
            locationManager.stopUpdatingLocation()
        }
    }

    public func startTracking() {
        totalDistanceMeters = 0.0
        previousLocation = nil
        trackingRequested = true
        guard isAuthorized else { return }
        isTracking = true
        locationManager.startUpdatingLocation()
    }

    public func stopTracking() {
        trackingRequested = false
        isTracking = false
        locationManager.stopUpdatingLocation()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last(where: isUsable) else { return }
        currentLocation = location
        currentSpeedKmH = max(0, location.speed * 3.6)

        if isTracking {
            if let prev = previousLocation {
                let delta = location.distance(from: prev)
                if delta < Self.maximumDistanceJumpMeters {
                    totalDistanceMeters += delta
                }
            }
            previousLocation = location
        }
    }

    private var isAuthorized: Bool {
        #if os(iOS)
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        #else
        authorizationStatus == .authorizedAlways
        #endif
    }

    private func isUsable(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0 &&
            location.horizontalAccuracy <= Self.maximumHorizontalAccuracyMeters &&
            abs(location.timestamp.timeIntervalSinceNow) <= Self.maximumLocationAge
    }

    private func updateBackgroundLocationSettings() {
        #if os(iOS)
        let hasAlways = authorizationStatus == .authorizedAlways
        locationManager.allowsBackgroundLocationUpdates = hasAlways
        locationManager.showsBackgroundLocationIndicator = hasAlways
        #endif
    }
}
