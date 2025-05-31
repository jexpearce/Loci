import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking = false
    
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    // Cache for geocoding results to avoid excessive API calls
    private var geocodeCache = [CLLocationCoordinate2D: String]()
    private let cacheDistance: CLLocationDistance = 50 // meters
    
    // Add one-time location completion handler
    private var oneTimeCompletion: ((CLLocation?) -> Void)?
    
    private override init() {
        super.init()
        setupLocationManager()
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        locationManager.delegate = self
        
        // Configure for best accuracy with power efficiency
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 20 // Update every 20 meters
        
        // Allow background location updates
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        
        // Enable significant location changes for better battery life
        locationManager.showsBackgroundLocationIndicator = true
        
        print("📍 Location manager configured")
    }
    
    // MARK: - Permissions
    
    func requestPermissions() {
        // Request always authorization for background tracking
        locationManager.requestAlwaysAuthorization()
    }
    
    // MARK: - Tracking Control
    
    func startTracking() {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            print("❌ Location permission not granted")
            return
        }
        
        isTracking = true
        locationManager.startUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        
        print("📍 Started location tracking")
    }
    
    func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        
        print("📍 Stopped location tracking")
    }
    
    /// Requests a single location fix, then calls the completion once.
    func requestOneTimeLocation(completion: @escaping (CLLocation?) -> Void) {
        let status = CLLocationManager.authorizationStatus()
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            locationManager.requestWhenInUseAuthorization()
            oneTimeCompletion = completion
            return
        }
        oneTimeCompletion = completion
        locationManager.requestLocation()
    }
    
    // MARK: - Reverse Geocoding
    
    func reverseGeocode(location: CLLocation, completion: @escaping (String?) -> Void) {
        // Check cache first
        if let cachedBuilding = checkGeocodeCache(for: location.coordinate) {
            print("📍 Using cached building: \(cachedBuilding)")
            completion(cachedBuilding)
            return
        }
        
        // Perform reverse geocoding
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let error = error {
                print("❌ Geocoding error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let placemark = placemarks?.first else {
                completion(nil)
                return
            }
            
            // Extract building-level information
            let building = self?.extractBuildingInfo(from: placemark)
            
            // Cache the result
            if let building = building {
                self?.cacheGeocodeResult(building, for: location.coordinate)
            }
            
            completion(building)
        }
    }
    
    private func extractBuildingInfo(from placemark: CLPlacemark) -> String? {
        // Priority order for location names
        if let name = placemark.name, !name.isEmpty {
            // Check if it's just a street address
            if let thoroughfare = placemark.thoroughfare,
               name.contains(thoroughfare) {
                // It's likely just an address, try to get a better name
                if let areaOfInterest = placemark.areasOfInterest?.first {
                    return areaOfInterest
                }
                // Use neighborhood or locality
                if let subLocality = placemark.subLocality {
                    return "\(subLocality) area"
                }
                if let locality = placemark.locality {
                    return "\(locality) area"
                }
            }
            return name
        }
        
        // Fallback options
        if let areaOfInterest = placemark.areasOfInterest?.first {
            return areaOfInterest
        }
        
        if let subThoroughfare = placemark.subThoroughfare,
           let thoroughfare = placemark.thoroughfare {
            return "\(subThoroughfare) \(thoroughfare)"
        }
        
        if let thoroughfare = placemark.thoroughfare {
            return thoroughfare
        }
        
        if let subLocality = placemark.subLocality {
            return subLocality
        }
        
        if let locality = placemark.locality {
            return locality
        }
        
        return "Unknown Location"
    }
    
    // MARK: - Geocoding Cache
    
    private func checkGeocodeCache(for coordinate: CLLocationCoordinate2D) -> String? {
        for (cachedCoord, building) in geocodeCache {
            let cachedLocation = CLLocation(latitude: cachedCoord.latitude, longitude: cachedCoord.longitude)
            let currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            
            if cachedLocation.distance(from: currentLocation) < cacheDistance {
                return building
            }
        }
        return nil
    }
    
    private func cacheGeocodeResult(_ building: String, for coordinate: CLLocationCoordinate2D) {
        geocodeCache[coordinate] = building
        
        // Limit cache size
        if geocodeCache.count > 100 {
            // Remove oldest entries (this is simplified, in production you'd want proper LRU)
            let keysToRemove = Array(geocodeCache.keys.prefix(20))
            keysToRemove.forEach { geocodeCache.removeValue(forKey: $0) }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Filter out low accuracy readings
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 100 {
            return
        }
        
        currentLocation = location
        
        // If there's a pending "oneTimeCompletion", call it exactly once and clear it
        if let completion = oneTimeCompletion {
            completion(location)
            oneTimeCompletion = nil
            return
        }

        // Otherwise, fall back to your existing "continuous" logic (if any)
        print("📍 Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // If we were waiting for a one‐time fix, inform the caller of failure
        if let completion = oneTimeCompletion {
            completion(nil)
            oneTimeCompletion = nil
            return
        }

        // Otherwise, handle error as you already did for continuous tracking
        print("❌ Location error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        // If user just granted permission and a one-time request is pending, request again
        if let completion = oneTimeCompletion {
            let status = manager.authorizationStatus
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                manager.requestLocation()
            }
        }
        
        switch authorizationStatus {
        case .authorizedAlways:
            print("✅ Location: Always authorized")
        case .authorizedWhenInUse:
            print("⚠️ Location: Only when in use (background tracking limited)")
        case .denied:
            print("❌ Location: Denied")
        case .restricted:
            print("❌ Location: Restricted")
        case .notDetermined:
            print("❓ Location: Not determined")
        @unknown default:
            print("❓ Location: Unknown status")
        }
    }
    
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        print("⏸️ Location updates paused")
    }
    
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        print("▶️ Location updates resumed")
    }
}

// MARK: - CLLocationCoordinate2D Hashable

extension CLLocationCoordinate2D: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
    
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
