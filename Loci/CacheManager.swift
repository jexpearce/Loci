import Foundation
import UIKit

// MARK: - Cache Configuration

struct CacheConfiguration {
    let maxMemorySize: Int          // Bytes
    let maxDiskSize: Int            // Bytes
    let defaultExpiration: TimeInterval
    let cleanupInterval: TimeInterval
    
    static let `default` = CacheConfiguration(
        maxMemorySize: 50 * 1024 * 1024,    // 50 MB
        maxDiskSize: 200 * 1024 * 1024,     // 200 MB
        defaultExpiration: 3600,             // 1 hour
        cleanupInterval: 300                 // 5 minutes
    )
    
    static let aggressive = CacheConfiguration(
        maxMemorySize: 20 * 1024 * 1024,    // 20 MB
        maxDiskSize: 100 * 1024 * 1024,     // 100 MB
        defaultExpiration: 1800,             // 30 minutes
        cleanupInterval: 180                 // 3 minutes
    )
}

// MARK: - Cache Entry

class CacheEntry<T: Codable>: Codable {
    let key: String
    let value: T
    let size: Int
    let createdAt: Date
    let expiresAt: Date
    var lastAccessedAt: Date
    var accessCount: Int
    
    init(key: String, value: T, size: Int, ttl: TimeInterval) {
        self.key = key
        self.value = value
        self.size = size
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(ttl)
        self.lastAccessedAt = Date()
        self.accessCount = 1
    }
    
    var isExpired: Bool {
        return Date() > expiresAt
    }
    
    func touch() {
        lastAccessedAt = Date()
        accessCount += 1
    }
    
    // Calculate priority score for eviction (higher = keep longer)
    var priority: Double {
        let age = Date().timeIntervalSince(createdAt)
        let recency = Date().timeIntervalSince(lastAccessedAt)
        let frequency = Double(accessCount)
        
        // Weighted score: frequency matters most, then recency, then age
        let frequencyScore = min(frequency / 10, 1.0) * 0.5
        let recencyScore = max(0, 1.0 - (recency / 3600)) * 0.3
        let ageScore = max(0, 1.0 - (age / 86400)) * 0.2
        
        return frequencyScore + recencyScore + ageScore
    }
}

// MARK: - Cache Manager

class CacheManager {
    static let shared = CacheManager()
    
    private let configuration: CacheConfiguration
    private let fileManager = FileManager.default
    private let cacheDirectoryURL: URL
    
    // Memory cache
    private var memoryCache = NSCache<NSString, AnyObject>()
    private var memoryCacheEntries = [String: CacheEntry<Data>]()
    private var currentMemorySize = 0
    
    // Disk cache tracking
    private var diskCacheIndex = [String: CacheMetadata]()
    private var currentDiskSize = 0
    
    // Queues
    private let cacheQueue = DispatchQueue(label: "com.loci.cache", attributes: .concurrent)
    private let cleanupQueue = DispatchQueue(label: "com.loci.cache.cleanup")
    
    // Cleanup
    private var cleanupTimer: Timer?
    
    // Cache namespaces
    enum CacheNamespace: String {
        case locations = "locations"
        case spotifyMetadata = "spotify"
        case userProfiles = "users"
        case images = "images"
        case analytics = "analytics"
        case general = "general"
    }
    
    private init(configuration: CacheConfiguration = .default) {
        self.configuration = configuration
        
        // Setup cache directory
        let documentsPath = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectoryURL = documentsPath.appendingPathComponent("com.loci.cache")
        
        setupCacheDirectory()
        setupMemoryCache()
        loadDiskIndex()
        startCleanupTimer()
        
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    // MARK: - Setup
    
    private func setupCacheDirectory() {
        try? fileManager.createDirectory(
            at: cacheDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // Create namespace directories
        for namespace in CacheNamespace.allCases {
            let namespaceURL = cacheDirectoryURL.appendingPathComponent(namespace.rawValue)
            try? fileManager.createDirectory(
                at: namespaceURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
    
    private func setupMemoryCache() {
        memoryCache.countLimit = 1000
        memoryCache.totalCostLimit = configuration.maxMemorySize
    }
    
    // MARK: - Core Cache Operations
    
    func set<T: Codable>(_ value: T, for key: String, namespace: CacheNamespace = .general, ttl: TimeInterval? = nil) {
        let fullKey = "\(namespace.rawValue):\(key)"
        let expiration = ttl ?? configuration.defaultExpiration
        
        cacheQueue.async(flags: .barrier) {
            do {
                let data = try JSONEncoder().encode(value)
                let size = data.count
                let entry = CacheEntry(key: fullKey, value: data, size: size, ttl: expiration)
                
                // Store in memory if small enough
                if size < self.configuration.maxMemorySize / 10 { // Only cache items < 10% of memory limit
                    self.storeInMemory(entry)
                }
                
                // Always store to disk
                self.storeToDisk(entry, namespace: namespace)
                
            } catch {
                print("❌ Cache encoding error: \(error)")
            }
        }
    }
    
    func get<T: Codable>(_ type: T.Type, for key: String, namespace: CacheNamespace = .general) -> T? {
        let fullKey = "\(namespace.rawValue):\(key)"
        
        return cacheQueue.sync {
            // Check memory first
            if let entry = memoryCacheEntries[fullKey], !entry.isExpired {
                entry.touch()
                return try? JSONDecoder().decode(type, from: entry.value)
            }
            
            // Check disk
            if let data = loadFromDisk(fullKey, namespace: namespace) {
                if let value = try? JSONDecoder().decode(type, from: data) {
                    // Promote to memory cache if frequently accessed
                    if let metadata = diskCacheIndex[fullKey], metadata.accessCount > 3 {
                        let entry = CacheEntry(
                            key: fullKey,
                            value: data,
                            size: data.count,
                            ttl: metadata.expiresAt.timeIntervalSince(Date())
                        )
                        storeInMemory(entry)
                    }
                    return value
                }
            }
            
            return nil
        }
    }
    
    func remove(key: String, namespace: CacheNamespace = .general) {
        let fullKey = "\(namespace.rawValue):\(key)"
        
        cacheQueue.async(flags: .barrier) {
            self.removeFromMemory(fullKey)
            self.removeFromDisk(fullKey, namespace: namespace)
        }
    }
    
    func clear(namespace: CacheNamespace? = nil) {
        cacheQueue.async(flags: .barrier) {
            if let namespace = namespace {
                // Clear specific namespace
                let prefix = "\(namespace.rawValue):"
                
                // Clear memory
                self.memoryCacheEntries.keys.filter { $0.hasPrefix(prefix) }.forEach {
                    self.removeFromMemory($0)
                }
                
                // Clear disk
                let namespaceURL = self.cacheDirectoryURL.appendingPathComponent(namespace.rawValue)
                try? self.fileManager.removeItem(at: namespaceURL)
                try? self.fileManager.createDirectory(at: namespaceURL, withIntermediateDirectories: true)
                
                // Update index
                self.diskCacheIndex = self.diskCacheIndex.filter { !$0.key.hasPrefix(prefix) }
            } else {
                // Clear everything
                self.clearAll()
            }
            
            self.saveDiskIndex()
        }
    }
    
    // MARK: - Specialized Cache Methods
    
    func cacheLocation(_ buildingName: String, for coordinate: CLLocationCoordinate2D) {
        let key = "\(coordinate.latitude),\(coordinate.longitude)"
        set(buildingName, for: key, namespace: .locations, ttl: 86400) // 24 hours
    }
    
    func getCachedLocation(for coordinate: CLLocationCoordinate2D, radius: Double = 50) -> String? {
        // Check exact match first
        let key = "\(coordinate.latitude),\(coordinate.longitude)"
        if let exact = get(String.self, for: key, namespace: .locations) {
            return exact
        }
        
        // Check nearby locations
        return cacheQueue.sync {
            for (cachedKey, _) in diskCacheIndex where cachedKey.hasPrefix("locations:") {
                let coords = cachedKey.replacingOccurrences(of: "locations:", with: "").split(separator: ",")
                guard coords.count == 2,
                      let lat = Double(coords[0]),
                      let lon = Double(coords[1]) else { continue }
                
                let cachedLocation = CLLocation(latitude: lat, longitude: lon)
                let currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                
                if cachedLocation.distance(from: currentLocation) <= radius {
                    return get(String.self, for: cachedKey.replacingOccurrences(of: "locations:", with: ""), namespace: .locations)
                }
            }
            return nil
        }
    }
    
    func cacheSpotifyTrack(_ track: SpotifyTrack) {
        set(track, for: track.id, namespace: .spotifyMetadata, ttl: 604800) // 7 days
        
        // Also cache by track name + artist for fuzzy matching
        let alternateKey = "\(track.name):\(track.artist)".lowercased()
        set(track.id, for: alternateKey, namespace: .spotifyMetadata, ttl: 604800)
    }
    
    func getCachedSpotifyTrack(id: String) -> SpotifyTrack? {
        return get(SpotifyTrack.self, for: id, namespace: .spotifyMetadata)
    }
    
    // MARK: - Memory Cache Management
    
    private func storeInMemory(_ entry: CacheEntry<Data>) {
        memoryCacheEntries[entry.key] = entry
        currentMemorySize += entry.size
        
        // Evict if needed
        if currentMemorySize > configuration.maxMemorySize {
            evictFromMemory()
        }
    }
    
    private func removeFromMemory(_ key: String) {
        if let entry = memoryCacheEntries.removeValue(forKey: key) {
            currentMemorySize -= entry.size
            memoryCache.removeObject(forKey: key as NSString)
        }
    }
    
    private func evictFromMemory() {
        // Sort by priority (lowest first)
        let sortedEntries = memoryCacheEntries.values.sorted { $0.priority < $1.priority }
        
        // Evict until we're under 80% of limit
        let targetSize = Int(Double(configuration.maxMemorySize) * 0.8)
        
        for entry in sortedEntries {
            if currentMemorySize <= targetSize { break }
            removeFromMemory(entry.key)
        }
    }
    
    // MARK: - Disk Cache Management
    
    private func storeToDisk(_ entry: CacheEntry<Data>, namespace: CacheNamespace) {
        let components = entry.key.components(separatedBy: ":")
        guard components.count >= 2 else { return }
        
        let filename = components.dropFirst().joined(separator: ":").addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? entry.key
        let fileURL = cacheDirectoryURL
            .appendingPathComponent(namespace.rawValue)
            .appendingPathComponent("\(filename).cache")
        
        do {
            try entry.value.write(to: fileURL)
            
            // Update index
            diskCacheIndex[entry.key] = CacheMetadata(
                key: entry.key,
                size: entry.size,
                createdAt: entry.createdAt,
                expiresAt: entry.expiresAt,
                accessCount: entry.accessCount,
                fileURL: fileURL
            )
            
            currentDiskSize += entry.size
            
            // Check disk space
            if currentDiskSize > configuration.maxDiskSize {
                cleanupQueue.async { self.evictFromDisk() }
            }
            
        } catch {
            print("❌ Cache disk write error: \(error)")
        }
    }
    
    private func loadFromDisk(_ key: String, namespace: CacheNamespace) -> Data? {
        guard let metadata = diskCacheIndex[key] else { return nil }
        
        // Check expiration
        if Date() > metadata.expiresAt {
            removeFromDisk(key, namespace: namespace)
            return nil
        }
        
        do {
            let data = try Data(contentsOf: metadata.fileURL)
            
            // Update access info
            diskCacheIndex[key]?.lastAccessedAt = Date()
            diskCacheIndex[key]?.accessCount += 1
            
            return data
        } catch {
            print("❌ Cache disk read error: \(error)")
            removeFromDisk(key, namespace: namespace)
            return nil
        }
    }
    
    private func removeFromDisk(_ key: String, namespace: CacheNamespace) {
        guard let metadata = diskCacheIndex.removeValue(forKey: key) else { return }
        
        currentDiskSize -= metadata.size
        try? fileManager.removeItem(at: metadata.fileURL)
    }
    
    private func evictFromDisk() {
        // Remove expired entries first
        let now = Date()
        let expiredKeys = diskCacheIndex.compactMap { $0.value.expiresAt < now ? $0.key : nil }
        
        for key in expiredKeys {
            if let metadata = diskCacheIndex[key] {
                let namespace = key.components(separatedBy: ":").first ?? "general"
                removeFromDisk(key, namespace: CacheNamespace(rawValue: namespace) ?? .general)
            }
        }
        
        // If still over limit, evict by priority
        if currentDiskSize > configuration.maxDiskSize {
            let targetSize = Int(Double(configuration.maxDiskSize) * 0.8)
            
            // Sort by priority score
            let sortedEntries = diskCacheIndex.values.sorted {
                $0.priority < $1.priority
            }
            
            for metadata in sortedEntries {
                if currentDiskSize <= targetSize { break }
                
                let namespace = metadata.key.components(separatedBy: ":").first ?? "general"
                removeFromDisk(metadata.key, namespace: CacheNamespace(rawValue: namespace) ?? .general)
            }
        }
        
        saveDiskIndex()
    }
    
    // MARK: - Persistence
    
    private func saveDiskIndex() {
        let indexURL = cacheDirectoryURL.appendingPathComponent("index.json")
        
        do {
            let data = try JSONEncoder().encode(diskCacheIndex)
            try data.write(to: indexURL)
        } catch {
            print("❌ Failed to save cache index: \(error)")
        }
    }
    
    private func loadDiskIndex() {
        let indexURL = cacheDirectoryURL.appendingPathComponent("index.json")
        
        do {
            let data = try Data(contentsOf: indexURL)
            diskCacheIndex = try JSONDecoder().decode([String: CacheMetadata].self, from: data)
            
            // Calculate current disk size
            currentDiskSize = diskCacheIndex.values.reduce(0) { $0 + $1.size }
            
            // Clean up any orphaned files
            cleanupQueue.async { self.cleanupOrphanedFiles() }
            
        } catch {
            // Index doesn't exist or is corrupted, rebuild it
            rebuildDiskIndex()
        }
    }
    
    private func rebuildDiskIndex() {
        diskCacheIndex.removeAll()
        currentDiskSize = 0
        
        for namespace in CacheNamespace.allCases {
            let namespaceURL = cacheDirectoryURL.appendingPathComponent(namespace.rawValue)
            
            guard let files = try? fileManager.contentsOfDirectory(at: namespaceURL, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]) else {
                continue
            }
            
            for fileURL in files where fileURL.pathExtension == "cache" {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    let size = attributes[.size] as? Int ?? 0
                    let createdAt = attributes[.creationDate] as? Date ?? Date()
                    
                    let filename = fileURL.deletingPathExtension().lastPathComponent
                    let key = "\(namespace.rawValue):\(filename.removingPercentEncoding ?? filename)"
                    
                    diskCacheIndex[key] = CacheMetadata(
                        key: key,
                        size: size,
                        createdAt: createdAt,
                        expiresAt: createdAt.addingTimeInterval(configuration.defaultExpiration),
                        accessCount: 0,
                        fileURL: fileURL
                    )
                    
                    currentDiskSize += size
                    
                } catch {
                    // Skip invalid files
                }
            }
        }
        
        saveDiskIndex()
    }
    
    private func cleanupOrphanedFiles() {
        let validURLs = Set(diskCacheIndex.values.map { $0.fileURL })
        
        for namespace in CacheNamespace.allCases {
            let namespaceURL = cacheDirectoryURL.appendingPathComponent(namespace.rawValue)
            
            guard let files = try? fileManager.contentsOfDirectory(at: namespaceURL, includingPropertiesForKeys: nil) else {
                continue
            }
            
            for fileURL in files where !validURLs.contains(fileURL) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
    
    // MARK: - Cleanup
    
    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.cleanupInterval,
            repeats: true
        ) { _ in
            self.performCleanup()
        }
    }
    
    private func performCleanup() {
        cleanupQueue.async {
            // Remove expired entries
            let now = Date()
            
            // Memory cleanup
            self.cacheQueue.async(flags: .barrier) {
                let expiredMemoryKeys = self.memoryCacheEntries.compactMap {
                    $0.value.isExpired ? $0.key : nil
                }
                expiredMemoryKeys.forEach { self.removeFromMemory($0) }
            }
            
            // Disk cleanup
            self.evictFromDisk()
        }
    }
    
    @objc private func handleMemoryWarning() {
        cacheQueue.async(flags: .barrier) {
            // Clear 50% of memory cache
            let entriesToRemove = self.memoryCacheEntries.values
                .sorted { $0.priority < $1.priority }
                .prefix(self.memoryCacheEntries.count / 2)
            
            entriesToRemove.forEach { self.removeFromMemory($0.key) }
        }
    }
    
    private func clearAll() {
        // Clear memory
        memoryCacheEntries.removeAll()
        memoryCache.removeAllObjects()
        currentMemorySize = 0
        
        // Clear disk
        try? fileManager.removeItem(at: cacheDirectoryURL)
        setupCacheDirectory()
        diskCacheIndex.removeAll()
        currentDiskSize = 0
        
        saveDiskIndex()
    }
    
    // MARK: - Statistics
    
    func getCacheStatistics() -> CacheStatistics {
        return cacheQueue.sync {
            CacheStatistics(
                memoryUsage: currentMemorySize,
                memoryLimit: configuration.maxMemorySize,
                diskUsage: currentDiskSize,
                diskLimit: configuration.maxDiskSize,
                totalEntries: memoryCacheEntries.count + diskCacheIndex.count,
                memoryEntries: memoryCacheEntries.count,
                diskEntries: diskCacheIndex.count,
                hitRate: calculateHitRate(),
                namespaceBreakdown: calculateNamespaceBreakdown()
            )
        }
    }
    
    private func calculateHitRate() -> Double {
        // This would require tracking hits/misses
        return 0.0 // Placeholder
    }
    
    private func calculateNamespaceBreakdown() -> [String: Int] {
        var breakdown: [String: Int] = [:]
        
        for key in diskCacheIndex.keys {
            let namespace = key.components(separatedBy: ":").first ?? "unknown"
            breakdown[namespace, default: 0] += 1
        }
        
        return breakdown
    }
}

// MARK: - Supporting Types

struct CacheMetadata: Codable {
    let key: String
    let size: Int
    let createdAt: Date
    let expiresAt: Date
    var lastAccessedAt: Date = Date()
    var accessCount: Int = 0
    let fileURL: URL
    
    var priority: Double {
        let age = Date().timeIntervalSince(createdAt)
        let recency = Date().timeIntervalSince(lastAccessedAt)
        let frequency = Double(accessCount)
        
        let frequencyScore = min(frequency / 10, 1.0) * 0.5
        let recencyScore = max(0, 1.0 - (recency / 3600)) * 0.3
        let ageScore = max(0, 1.0 - (age / 86400)) * 0.2
        
        return frequencyScore + recencyScore + ageScore
    }
}

struct CacheStatistics {
    let memoryUsage: Int
    let memoryLimit: Int
    let diskUsage: Int
    let diskLimit: Int
    let totalEntries: Int
    let memoryEntries: Int
    let diskEntries: Int
    let hitRate: Double
    let namespaceBreakdown: [String: Int]
    
    var memoryUsagePercentage: Double {
        Double(memoryUsage) / Double(memoryLimit)
    }
    
    var diskUsagePercentage: Double {
        Double(diskUsage) / Double(diskLimit)
    }
}

// Make CacheNamespace CaseIterable for convenience
extension CacheManager.CacheNamespace: CaseIterable {}

// MARK: - CLLocationCoordinate2D Extension for Cache

extension CLLocationCoordinate2D {
    var cacheKey: String {
        return "\(latitude),\(longitude)"
    }
}
