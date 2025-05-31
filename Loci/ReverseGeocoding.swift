import Foundation
import CoreLocation
import Combine

// MARK: - Reverse Geocoding Service

class ReverseGeocoding: NSObject, ObservableObject {
    static let shared = ReverseGeocoding()
    
    // Geocoders
    private let appleGeocoder = CLGeocoder()
    private let cacheManager = CacheManager.shared
    
    // Queue management
    private let geocodingQueue = DispatchQueue(label: "com.loci.geocoding", qos: .background)
    private var pendingRequests = [UUID: GeocodeRequest]()
    private let requestLock = NSLock()
    
    // Rate limiting
    private var lastGeocodingTime: Date?
    private let geocodingInterval: TimeInterval = 1.0 // Apple recommends 1 request per second
    private var requestTimer: Timer?
    
    // Batch processing
    private let batchSize = 5
    private var isProcessing = false
    
    // Statistics
    @Published var cacheHitRate: Double = 0.0
    private var totalRequests = 0
    private var cacheHits = 0
    
    // MARK: - Rate Limiting & Throttling
    
    private var isGeocoding = false
    private var lastGeocodeTime = Date.distantPast
    private let minimumGeocodeInterval: TimeInterval = 2.0 // 2 seconds between requests
    
    private override init() {
        super.init()
        startBatchProcessor()
    }
    
    // MARK: - Public Interface
    
    /// Reverse geocode with intelligent caching and fallbacks
    func reverseGeocode(
        location: CLLocation,
        completion: @escaping (BuildingInfo?) -> Void
    ) {
        // Check cache first
        if let cached = checkCache(for: location) {
            cacheHits += 1
            updateCacheHitRate()
            completion(cached)
            return
        }
        
        // Add to pending queue
        let request = GeocodeRequest(
            id: UUID(),
            location: location,
            completion: completion,
            timestamp: Date(),
            retryCount: 0
        )
        
        requestLock.lock()
        pendingRequests[request.id] = request
        requestLock.unlock()
        
        totalRequests += 1
        updateCacheHitRate()
    }
    
    /// Batch reverse geocode for session reconciliation
    func batchReverseGeocode(
        locations: [CLLocation]
    ) async -> [CLLocation: BuildingInfo] {
        var results: [CLLocation: BuildingInfo] = [:]
        
        // Process in chunks to respect rate limits
        for chunk in locations.chunked(into: batchSize) {
            await withTaskGroup(of: (CLLocation, BuildingInfo?).self) { group in
                for location in chunk {
                    group.addTask {
                        let building = await self.reverseGeocodeAsync(location: location)
                        return (location, building)
                    }
                }
                
                for await (location, building) in group {
                    if let building = building {
                        results[location] = building
                    }
                }
            }
            
            // Rate limiting between chunks
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        
        return results
    }
    
    // MARK: - Async Interface
    
    func reverseGeocodeAsync(location: CLLocation) async -> BuildingInfo? {
        // Check cache first
        if let cached = checkCache(for: location) {
            return cached
        }
        
        // Throttle requests to avoid rate limiting
        let now = Date()
        let timeSinceLastGeocode = now.timeIntervalSince(lastGeocodeTime)
        
        if timeSinceLastGeocode < minimumGeocodeInterval {
            let delay = minimumGeocodeInterval - timeSinceLastGeocode
            print("🕐 Throttling geocode request, waiting \(delay)s")
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        // Prevent concurrent requests
        guard !isGeocoding else {
            print("⏳ Geocoding already in progress, skipping")
            return nil
        }
        
        isGeocoding = true
        lastGeocodeTime = Date()
        
        defer {
            isGeocoding = false
        }
        
        return await withCheckedContinuation { continuation in
            reverseGeocode(location: location) { building in
                continuation.resume(returning: building)
            }
        }
    }
    
    // MARK: - Batch Processing
    
    private func startBatchProcessor() {
        requestTimer = Timer.scheduledTimer(
            withTimeInterval: geocodingInterval,
            repeats: true
        ) { _ in
            self.processPendingRequests()
        }
    }
    
    private func processPendingRequests() {
        guard !isProcessing else { return }
        
        requestLock.lock()
        let requests = Array(pendingRequests.values.prefix(batchSize))
        requests.forEach { pendingRequests.removeValue(forKey: $0.id) }
        requestLock.unlock()
        
        guard !requests.isEmpty else { return }
        
        isProcessing = true
        
        geocodingQueue.async {
            for request in requests {
                self.performGeocoding(location: request.location) { building in
                    DispatchQueue.main.async {
                        request.completion(building)
                    }
                }
                
                // Small delay between requests
                Thread.sleep(forTimeInterval: 0.2)
            }
            
            self.isProcessing = false
        }
    }
    
    // MARK: - Core Geocoding
    
    private func performGeocoding(
        location: CLLocation,
        completion: @escaping (BuildingInfo?) -> Void
    ) {
        appleGeocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let error = error {
                print("❌ Geocoding error: \(error)")
                
                // Try fallback methods
                self?.performFallbackGeocoding(location: location, completion: completion)
                return
            }
            
            guard let placemark = placemarks?.first else {
                completion(nil)
                return
            }
            
            // Extract building info
            let building = self?.extractBuildingInfo(from: placemark, location: location)
            
            // Cache result
            if let building = building {
                self?.cacheResult(building, for: location)
            }
            
            completion(building)
        }
    }
    
    private func performFallbackGeocoding(
        location: CLLocation,
        completion: @escaping (BuildingInfo?) -> Void
    ) {
        // Fallback 1: Check nearby cached locations
        if let nearby = findNearbyCachedBuilding(for: location) {
            completion(nearby)
            return
        }
        
        // Fallback 2: Use clustering service
        let cluster = LocationClusteringService().findOrCreateCluster(for: location)
        let fallbackBuilding = BuildingInfo(
            name: cluster.primaryBuilding ?? "Location \(cluster.id.uuidString.prefix(8))",
            address: nil,
            category: .unknown,
            coordinates: location.coordinate,
            confidence: 0.3,
            neighborhood: nil,
            city: nil,
            postalCode: nil,
            country: nil
        )
        
        completion(fallbackBuilding)
    }
    
    // MARK: - Building Extraction
    
    private func extractBuildingInfo(
        from placemark: CLPlacemark,
        location: CLLocation
    ) -> BuildingInfo {
        // Priority order for building names
        var buildingName: String?
        var category: BuildingCategory = .unknown
        var confidence: Double = 1.0
        
        // 1. Check for named location (best case)
        if let name = placemark.name,
           !isStreetAddress(name, placemark: placemark) {
            buildingName = name
            category = categorizeBuilding(name: name, placemark: placemark)
            confidence = 1.0
        }
        
        // 2. Areas of interest
        else if let areasOfInterest = placemark.areasOfInterest,
                let area = areasOfInterest.first {
            buildingName = area
            category = categorizeBuilding(name: area, placemark: placemark)
            confidence = 0.9
        }
        
        // 3. Infer from address components
        else {
            buildingName = inferBuildingName(from: placemark)
            category = .unknown
            confidence = 0.6
        }
        
        // Build address
        let address = formatAddress(from: placemark)
        
        return BuildingInfo(
            name: buildingName ?? "Unknown Location",
            address: address,
            category: category,
            coordinates: location.coordinate,
            confidence: confidence,
            neighborhood: placemark.subLocality,
            city: placemark.locality,
            postalCode: placemark.postalCode,
            country: placemark.country
        )
    }
    
    private func isStreetAddress(_ name: String, placemark: CLPlacemark) -> Bool {
        // Check if name is just a street address
        if let thoroughfare = placemark.thoroughfare {
            return name.contains(thoroughfare)
        }
        
        // Check for common address patterns
        let addressPattern = #"^\d+\s+"#
        return name.range(of: addressPattern, options: .regularExpression) != nil
    }
    
    private func inferBuildingName(from placemark: CLPlacemark) -> String {
        // Try to build a meaningful name from components
        var components: [String] = []
        
        if let subThoroughfare = placemark.subThoroughfare {
            components.append(subThoroughfare)
        }
        
        if let thoroughfare = placemark.thoroughfare {
            components.append(thoroughfare)
        }
        
        if components.isEmpty, let subLocality = placemark.subLocality {
            return "\(subLocality) area"
        }
        
        return components.joined(separator: " ")
    }
    
    private func formatAddress(from placemark: CLPlacemark) -> String {
        var addressComponents: [String] = []
        
        if let subThoroughfare = placemark.subThoroughfare {
            addressComponents.append(subThoroughfare)
        }
        
        if let thoroughfare = placemark.thoroughfare {
            addressComponents.append(thoroughfare)
        }
        
        if let locality = placemark.locality {
            addressComponents.append(locality)
        }
        
        if let postalCode = placemark.postalCode {
            addressComponents.append(postalCode)
        }
        
        return addressComponents.joined(separator: ", ")
    }
    
    private func categorizeBuilding(name: String, placemark: CLPlacemark) -> BuildingCategory {
        let lowercasedName = name.lowercased()
        
        // Check common patterns
        if lowercasedName.contains("coffee") || lowercasedName.contains("café") || lowercasedName.contains("starbucks") {
            return .cafe
        } else if lowercasedName.contains("restaurant") || lowercasedName.contains("pizza") || lowercasedName.contains("burger") {
            return .restaurant
        } else if lowercasedName.contains("bar") || lowercasedName.contains("pub") || lowercasedName.contains("club") {
            return .bar
        } else if lowercasedName.contains("gym") || lowercasedName.contains("fitness") {
            return .gym
        } else if lowercasedName.contains("store") || lowercasedName.contains("shop") || lowercasedName.contains("market") {
            return .retail
        } else if lowercasedName.contains("office") || lowercasedName.contains("building") {
            return .office
        } else if lowercasedName.contains("university") || lowercasedName.contains("college") || lowercasedName.contains("school") {
            return .education
        } else if lowercasedName.contains("park") || lowercasedName.contains("garden") {
            return .park
        } else if lowercasedName.contains("station") || lowercasedName.contains("airport") {
            return .transport
        } else if lowercasedName.contains("home") || lowercasedName.contains("apartment") || lowercasedName.contains("residence") {
            return .residential
        }
        
        return .other
    }
    
    // MARK: - Caching
    
    private func checkCache(for location: CLLocation) -> BuildingInfo? {
        // Direct cache hit
        let cacheKey = location.coordinate.cacheKey
        if let cached = cacheManager.get(BuildingInfo.self, for: cacheKey, namespace: .locations) {
            return cached
        }
        
        // Check nearby locations with improved boundary detection
        return findNearbyCachedBuilding(for: location)
    }
    
    private func findNearbyCachedBuilding(for location: CLLocation) -> BuildingInfo? {
        // Use CacheManager's spatial lookup with building-appropriate radius
        if let cachedName = cacheManager.getCachedLocation(for: location.coordinate, radius: 30) {
            // For buildings, use smaller radius (30m) for better accuracy
            return BuildingInfo(
                name: cachedName,
                address: nil,
                category: .unknown,
                coordinates: location.coordinate,
                confidence: 0.8,
                neighborhood: nil,
                city: nil,
                postalCode: nil,
                country: nil
            )
        }
        
        return nil
    }
    
    private func cacheResult(_ building: BuildingInfo, for location: CLLocation) {
        // Cache the full BuildingInfo with building-specific TTL
        let cacheKey = location.coordinate.cacheKey
        let ttl: TimeInterval = building.confidence > 0.8 ? 86400 : 3600 // 24h for high confidence, 1h for low
        cacheManager.set(building, for: cacheKey, namespace: .locations, ttl: ttl)
        
        // Also cache just the name for nearby lookups with building name and confidence
        let enrichedName = building.confidence > 0.8 ? building.name : "\(building.name) (uncertain)"
        cacheManager.cacheLocation(enrichedName, for: location.coordinate)
    }
    
    // MARK: - Statistics
    
    private func updateCacheHitRate() {
        guard totalRequests > 0 else {
            cacheHitRate = 0.0
            return
        }
        
        cacheHitRate = Double(cacheHits) / Double(totalRequests)
    }
    
    func resetStatistics() {
        totalRequests = 0
        cacheHits = 0
        cacheHitRate = 0.0
    }
}

// MARK: - Supporting Types

struct BuildingInfo: Codable {
    let name: String
    let address: String?
    let category: BuildingCategory
    let coordinates: CLLocationCoordinate2D
    let confidence: Double // 0.0 to 1.0
    
    // Additional metadata
    let neighborhood: String?
    let city: String?
    let postalCode: String?
    let country: String?
    
    var displayName: String {
        if confidence > 0.8 {
            return name
        } else if let neighborhood = neighborhood {
            return "\(name) • \(neighborhood)"
        } else {
            return name
        }
    }
}

enum BuildingCategory: String, Codable, CaseIterable {
    case cafe = "Café"
    case restaurant = "Restaurant"
    case bar = "Bar"
    case gym = "Gym"
    case retail = "Retail"
    case office = "Office"
    case education = "Education"
    case park = "Park"
    case transport = "Transport"
    case residential = "Residential"
    case entertainment = "Entertainment"
    case other = "Other"
    case unknown = "Unknown"
    
    var emoji: String {
        switch self {
        case .cafe: return "☕"
        case .restaurant: return "🍽️"
        case .bar: return "🍺"
        case .gym: return "💪"
        case .retail: return "🛍️"
        case .office: return "🏢"
        case .education: return "🎓"
        case .park: return "🌳"
        case .transport: return "🚇"
        case .residential: return "🏠"
        case .entertainment: return "🎭"
        case .other: return "📍"
        case .unknown: return "❓"
        }
    }
}

// Complete the cut-off struct
private struct GeocodeRequest {
    let id: UUID
    let location: CLLocation
    let completion: (BuildingInfo?) -> Void
    let timestamp: Date
    let retryCount: Int
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - CLLocationCoordinate2D Codable

extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}
